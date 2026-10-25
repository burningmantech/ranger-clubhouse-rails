#!/usr/bin/env ruby
# Automated diagnostic to identify cropping transformation bug
# Creates 1024×1536 grid image and tests transformation formula

require "vips"

puts "=" * 80
puts "AUTOMATED CROPPING DIAGNOSTIC - Bug Detection"
puts "=" * 80
puts

# Create 1024×1536 test image with labeled grid (2:3 aspect ratio)
width = 1024
height = 1536
canvas_w = 350
canvas_h = 450

puts "Test Image: #{width}×#{height}"
puts "Canvas: #{canvas_w}×#{canvas_h}"
puts

# Create 4×6 grid for precise identification
# Each cell is 256×256 pixels
# Numbered 1-24 from left-to-right, top-to-bottom
grid_cols = 4
grid_rows = 6
cell_w = width / grid_cols   # 256
cell_h = height / grid_rows  # 256

puts "Grid: #{grid_cols}×#{grid_rows} (#{cell_w}×#{cell_h} per cell)"
puts "Layout:"
puts "   1   2   3   4   ← TOP"
puts "   5   6   7   8"
puts "   9  10  11  12   ← MID"
puts "  13  14  15  16"
puts "  17  18  19  20"
puts "  21  22  23  24   ← BOTTOM"
puts

# Create cells with unique values
cells = 24.times.map do |i|
  # Values: 10, 20, 30, ..., 240 (for cells 1-24)
  value = ((i + 1) * 10).clamp(0, 255)
  Vips::Image.black(cell_w, cell_h) + value
end

# Assemble grid
rows = 6.times.map do |row_idx|
  row_cells = cells[row_idx * 4, 4]
  row_cells[0].join(row_cells[1], :horizontal)
              .join(row_cells[2], :horizontal)
              .join(row_cells[3], :horizontal)
end

grid_image = rows[0]
5.times { |i| grid_image = grid_image.join(rows[i+1], :vertical) }

puts "Grid created: #{grid_image.width}×#{grid_image.height}"
puts

# Test cases from actual user data
# These represent real CropperJS transformations
test_cases = [
  {
    name: "TOP-LEFT positioning (user's actual test)",
    scale: 0.5190,
    translate_x: -246.14,
    translate_y: -370.98,
    expected_region: "top-left quadrant",
    expected_cells: [1, 2, 5, 6, 9, 10]  # Top-left region
  },
  {
    name: "CENTERED positioning",
    scale: 0.35,
    translate_x: -330.0,
    translate_y: -495.0,
    expected_region: "center of image",
    expected_cells: [6, 7, 10, 11, 14, 15]  # Center region
  },
  {
    name: "Identity test (no transform)",
    scale: 1.0,
    translate_x: 0.0,
    translate_y: 0.0,
    expected_region: "exact top-left corner (350×450)",
    expected_cells: [1, 2, 5]  # Just top-left cells that fit in 350×450
  }
]

# Test different formula variations
formulas = [
  {
    name: "CURRENT (standard Canvas2D inverse)",
    calc: ->(scale, tx, ty) {
      inv_scale = 1.0 / scale
      inv_tx = -tx * inv_scale
      inv_ty = -ty * inv_scale
      { inv_scale: inv_scale, inv_tx: inv_tx, inv_ty: inv_ty }
    }
  },
  {
    name: "WITH canvas center compensation",
    calc: ->(scale, tx, ty) {
      canvas_cx = 175.0
      canvas_cy = 225.0
      inv_scale = 1.0 / scale
      inv_tx = -(tx + canvas_cx) * inv_scale
      inv_ty = -(ty + canvas_cy) * inv_scale
      { inv_scale: inv_scale, inv_tx: inv_tx, inv_ty: inv_ty }
    }
  },
  {
    name: "NO negation (flipped sign)",
    calc: ->(scale, tx, ty) {
      inv_scale = 1.0 / scale
      inv_tx = tx * inv_scale
      inv_ty = ty * inv_scale
      { inv_scale: inv_scale, inv_tx: inv_tx, inv_ty: inv_ty }
    }
  }
]

test_cases.each_with_index do |test_case, test_idx|
  puts "=" * 80
  puts "TEST #{test_idx + 1}: #{test_case[:name]}"
  puts "=" * 80
  puts "Scale: #{test_case[:scale]}, Translate: (#{test_case[:translate_x]}, #{test_case[:translate_y]})"
  puts "Expected: #{test_case[:expected_region]}"
  puts

  formulas.each do |formula|
    result = formula[:calc].call(test_case[:scale], test_case[:translate_x], test_case[:translate_y])

    # Map canvas corners
    corners = [[0, 0], [canvas_w, 0], [0, canvas_h], [canvas_w, canvas_h]]
    orig_coords = corners.map do |cx, cy|
      ox = cx * result[:inv_scale] + result[:inv_tx]
      oy = cy * result[:inv_scale] + result[:inv_ty]
      [ox, oy]
    end

    min_x = [orig_coords.map(&:first).min, 0].max.floor
    max_x = [orig_coords.map(&:first).max, width].min.ceil
    min_y = [orig_coords.map(&:last).min, 0].max.floor
    max_y = [orig_coords.map(&:last).max, height].min.ceil

    extract_w = max_x - min_x
    extract_h = max_y - min_y

    puts "#{formula[:name]}:"
    puts "  inv_translate: (#{result[:inv_tx].round(2)}, #{result[:inv_ty].round(2)})"
    puts "  Canvas TL (0,0) → Original (#{orig_coords[0][0].round(1)}, #{orig_coords[0][1].round(1)})"
    puts "  Extraction: (#{min_x}, #{min_y}, #{extract_w}, #{extract_h})"

    if extract_w > 0 && extract_h > 0 && min_x < width && min_y < height
      # Extract and resize
      extracted = grid_image.extract_area(min_x, min_y, extract_w, extract_h)
      resized = extracted.resize(canvas_w.to_f / extracted.width, vscale: canvas_h.to_f / extracted.height, kernel: :lanczos3)

      # Sample key positions to identify cells
      samples = [
        resized.getpoint(10, 10)[0],      # TL corner
        resized.getpoint(340, 10)[0],     # TR corner
        resized.getpoint(175, 225)[0],    # Center
        resized.getpoint(10, 440)[0],     # BL corner
        resized.getpoint(340, 440)[0]     # BR corner
      ]

      # Identify cells (value / 10 = cell number)
      cells_detected = samples.map { |v| (v / 10.0).round }.uniq.sort

      avg = resized.avg

      puts "  Result avg: #{avg.round(1)}, Cells detected: #{cells_detected.inspect}"

      # Check if matches expected
      matches = (cells_detected & test_case[:expected_cells]).length
      total_expected = test_case[:expected_cells].length

      if matches >= (total_expected * 0.5)  # At least 50% match
        puts "  ✓ MATCHES expected region (#{matches}/#{total_expected} cells)"
      else
        puts "  ❌ WRONG region (only #{matches}/#{total_expected} expected cells)"
      end
    else
      puts "  ❌ INVALID extraction bounds"
    end
    puts
  end
end

puts "=" * 80
puts "DIAGNOSIS:"
puts "The formula that shows ✓ MATCHES for ALL tests is the correct one."
puts "If NO formula works for all tests, there's a deeper issue in coordinate space."
puts "=" * 80
