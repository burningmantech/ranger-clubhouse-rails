#!/usr/bin/env ruby
# Comprehensive diagnostic for CropperJS transformation
# Creates grid test image and tests both resize→extract and extract→resize

require "vips"

puts "=" * 80
puts "COMPREHENSIVE CROPPERJS TRANSFORMATION DIAGNOSTIC"
puts "=" * 80
puts

# Create test image with 7:9 aspect ratio, ≥1000px (passport photo standard)
# Using 1400×1800 (7×200 : 9×200)
width = 1400
height = 1800

# Canvas is 350×450 (7×50 : 9×50) - same aspect ratio
canvas_w = 350
canvas_h = 450

puts "Creating #{width}×#{height} grid test image (7:9 aspect ratio)..."
puts "Canvas: #{canvas_w}×#{canvas_h} (7:9 aspect ratio)"
puts

# Create 4×4 grid for better granularity (each cell is 350×450, same as canvas!)
grid_cols = 4
grid_rows = 4
cell_width = width / grid_cols   # 350
cell_height = height / grid_rows  # 450

puts "Grid: #{grid_cols}×#{grid_rows} (#{cell_width}px × #{cell_height}px per cell)"
puts "NOTE: Each cell is EXACTLY canvas size (350×450)!"
puts

cells = 16.times.map do |i|
  # Cell values: 16, 32, 48, ..., 255
  cell_value = ((i + 1) * 16).clamp(0, 255)
  Vips::Image.black(cell_width, cell_height) + cell_value
end

# Assemble grid
rows = 4.times.map do |row_idx|
  row_cells = cells[row_idx * 4, 4]
  row_cells[0].join(row_cells[1], :horizontal)
              .join(row_cells[2], :horizontal)
              .join(row_cells[3], :horizontal)
end

grid_image = rows[0].join(rows[1], :vertical)
                  .join(rows[2], :vertical)
                  .join(rows[3], :vertical)

puts "Grid layout (pixel values):"
puts "   1(16)   2(32)   3(48)   4(64)   ← TOP row"
puts "   5(80)   6(96)   7(112)  8(128)  ← ROW 2"
puts "   9(144) 10(160) 11(176) 12(192) ← ROW 3"
puts "  13(208) 14(224) 15(240) 16(255) ← BOTTOM row"
puts "  At 1:1 zoom, canvas shows exactly 1 cell"
puts

# Test cases with 1400×1800 image
# At 1:1 zoom (scale=1.0), user should see exactly 1 cell (350×450)
# At scale=0.25, entire image fits in canvas
# User's typical scale ~0.64 means zoomed in

test_cases = [
  {
    name: "Show cell 1 (TOP-LEFT) at 1:1 zoom",
    scale_x: 1.0,
    scale_y: 1.0,
    # To show cell 1: its center (175,225) should appear at canvas center (175,225)
    # So translate should be minimal/zero
    translate_x: 0.0,
    translate_y: 0.0,
    expected_cells: [1], # Should show ONLY cell 1
    expected_avg: 16
  },
  {
    name: "Show cell 4 (TOP-RIGHT) at 1:1 zoom",
    scale_x: 1.0,
    scale_y: 1.0,
    # To show cell 4: region (1050,0,1400,450) → canvas
    # Cell 4 center is at (1225,225), should map to canvas (175,225)
    # Translate needed: 175 - 1225 = -1050
    translate_x: -1050.0,
    translate_y: 0.0,
    expected_cells: [4], # Should show ONLY cell 4
    expected_avg: 64
  },
  {
    name: "Entire image scaled to fit",
    scale_x: 0.25,
    scale_y: 0.25,
    # Entire image at 0.25 scale = 350×450, should fit perfectly
    translate_x: 0.0,
    translate_y: 0.0,
    expected_cells: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16], # All cells
    expected_avg: 136  # Average of 1-16
  }
]

# Test different approaches
approaches = [
  {
    name: "CURRENT IMPLEMENTATION (with aspect ratio fix)",
    process: ->(img, left, top, w, h, profile_w, profile_h) {
      # This matches the current code exactly
      extracted = img.extract_area(left, top, w, h)

      # Check if aspect ratio needs adjustment
      extracted_aspect = extracted.width.to_f / extracted.height
      target_aspect = profile_w.to_f / profile_h

      if (extracted_aspect - target_aspect).abs > 0.001
        if extracted_aspect > target_aspect
          # Too wide, reduce width
          new_w = (extracted.height * target_aspect).round
          extracted = extracted.extract_area(0, 0, new_w, extracted.height)
        else
          # Too tall, reduce height
          new_h = (extracted.width / target_aspect).round
          extracted = extracted.extract_area(0, 0, extracted.width, new_h)
        end
      end

      extracted.resize(profile_w.to_f / extracted.width, vscale: profile_h.to_f / extracted.height, kernel: :lanczos3)
    }
  },
  {
    name: "SIMPLE EXTRACT then RESIZE (no aspect fix)",
    process: ->(img, left, top, w, h, profile_w, profile_h) {
      extracted = img.extract_area(left, top, w, h)
      extracted.resize(profile_w.to_f / extracted.width, vscale: profile_h.to_f / extracted.height, kernel: :lanczos3)
    }
  },
  {
    name: "RESIZE then EXTRACT",
    process: ->(img, left, top, w, h, profile_w, profile_h) {
      # First resize entire image to canvas scale
      # Canvas is 350×450, we need to figure out what scale makes the crop region fit
      # The crop region is w×h in original, and should become close to 350×450

      # Calculate scale to fit extraction region into profile
      scale_x_needed = profile_w.to_f / w
      scale_y_needed = profile_h.to_f / h

      # Resize entire image
      resized = img.resize(scale_x_needed, vscale: scale_y_needed, kernel: :lanczos3)

      # After resize, extraction coordinates scale proportionally
      scaled_left = (left * scale_x_needed).round.clamp(0, resized.width - 1)
      scaled_top = (top * scale_y_needed).round.clamp(0, resized.height - 1)
      scaled_w = [(w * scale_x_needed).round, profile_w].min
      scaled_h = [(h * scale_y_needed).round, profile_h].min

      # Ensure we don't exceed image bounds
      scaled_w = [scaled_w, resized.width - scaled_left].min
      scaled_h = [scaled_h, resized.height - scaled_top].min

      if scaled_w > 0 && scaled_h > 0
        resized.extract_area(scaled_left, scaled_top, scaled_w, scaled_h)
      else
        # Return black image if extraction would fail
        Vips::Image.black(profile_w, profile_h)
      end
    }
  }
]

test_cases.each_with_index do |test_case, test_idx|
  puts "=" * 80
  puts "TEST #{test_idx + 1}: #{test_case[:name]}"
  puts "=" * 80
  puts "Parameters: scale=#{test_case[:scale_x]}, translate=(#{test_case[:translate_x]}, #{test_case[:translate_y]})"
  puts "Expected: Should show cells #{test_case[:expected_cells].inspect} (avg ~#{test_case[:expected_avg]})"
  puts

  # Calculate inverse using the canvas center compensation formula
  scale = test_case[:scale_x]
  tx = test_case[:translate_x]
  ty = test_case[:translate_y]
  canvas_cx = 175.0
  canvas_cy = 225.0
  img_cx = width / 2.0  # 375
  img_cy = height / 2.0 # 562.5

  # Test the current formula
  inv_scale = 1.0 / scale
  inv_tx_current = -(tx + canvas_cx) * inv_scale
  inv_ty_current = -(ty + canvas_cy) * inv_scale

  # Also test without canvas center
  inv_tx_direct = -tx * inv_scale
  inv_ty_direct = -ty * inv_scale

  puts "Formula comparison:"
  puts "  Current (with canvas_center): inv_tx = #{inv_tx_current.round(2)}, inv_ty = #{inv_ty_current.round(2)}"
  puts "  Direct (no canvas_center): inv_tx = #{inv_tx_direct.round(2)}, inv_ty = #{inv_ty_direct.round(2)}"

  inv_tx = inv_tx_current
  inv_ty = inv_ty_current

  # Map canvas corners to original
  corners = [[0, 0], [350, 0], [0, 450], [350, 450]]
  orig_coords = corners.map { |cx, cy| [cx * inv_scale + inv_tx, cy * inv_scale + inv_ty] }

  min_x = orig_coords.map(&:first).min
  max_x = orig_coords.map(&:first).max
  min_y = orig_coords.map(&:last).min
  max_y = orig_coords.map(&:last).max

  puts "Mapped canvas corners to original: #{orig_coords.map { |x, y| "(#{x.round(1)},#{y.round(1)})" }.join(', ')}"
  puts "Bounding box: (#{min_x.round(1)}, #{min_y.round(1)}) to (#{max_x.round(1)}, #{max_y.round(1)})"
  puts

  approaches.each do |approach|
    puts "--- #{approach[:name]} ---"

    # Clamp to image bounds
    extract_left = [min_x.floor, 0].max
    extract_top = [min_y.floor, 0].max
    extract_right = [max_x.ceil, width].min
    extract_bottom = [max_y.ceil, height].min
    extract_w = extract_right - extract_left
    extract_h = extract_bottom - extract_top

    puts "Extraction: (#{extract_left}, #{extract_top}, #{extract_w}, #{extract_h})"

    if extract_w > 0 && extract_h > 0
      result = approach[:process].call(grid_image, extract_left, extract_top, extract_w, extract_h, 350, 450)

      # Analyze result by sampling different regions
      samples = {
        "TL corner" => result.getpoint(10, 10)[0],
        "TR corner" => result.getpoint(340, 10)[0],
        "Center" => result.getpoint(175, 225)[0],
        "BL corner" => result.getpoint(10, 440)[0],
        "BR corner" => result.getpoint(340, 440)[0]
      }

      avg = result.avg

      puts "Result: #{result.width}×#{result.height}, average pixel value: #{avg.round(2)}"
      puts "Sample values: #{samples.inspect}"

      # Identify which cells are present based on pixel values
      present_cells = []
      samples.each do |location, value|
        cell_num = ((value / 28.0).round).clamp(1, 9)
        present_cells << cell_num
      end

      puts "Detected cells in result: #{present_cells.uniq.sort.inspect}"

      # Check if matches expected
      if (present_cells & test_case[:expected_cells]).length >= 2
        puts "✓ MATCHES expected cells #{test_case[:expected_cells].inspect}"
      else
        puts "❌ WRONG cells (expected #{test_case[:expected_cells].inspect})"
      end
    else
      puts "❌ Invalid extraction bounds"
    end
    puts
  end
end

puts "=" * 80
puts "CONCLUSION: The approach that matches expected cells for ALL tests is correct!"
puts "=" * 80
