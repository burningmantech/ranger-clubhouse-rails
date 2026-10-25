#!/usr/bin/env ruby
# Systematic search for correct formula using actual grid test data
# Tests multiple offset variations to find which produces correct cell extraction

require "vips"

# Create grid
width, height = 750, 1125
cell_w, cell_h = 250, 375
cells = 9.times.map { |i| Vips::Image.black(cell_w, cell_h) + ((i + 1) * 28) }
row1 = cells[0].join(cells[1], :horizontal).join(cells[2], :horizontal)
row2 = cells[3].join(cells[4], :horizontal).join(cells[5], :horizontal)
row3 = cells[6].join(cells[7], :horizontal).join(cells[8], :horizontal)
grid = row1.join(row2, :vertical).join(row3, :vertical)

canvas_w, canvas_h = 350, 450
canvas_cx, canvas_cy = canvas_w / 2.0, canvas_h / 2.0

# User's actual test data
test_data = {
  name: "Centered (should show Cell 5)",
  scale: 0.5856,
  tx: -203.8,
  ty: -346.6,
  expected_primary_cell: 5,
  expected_cells: [5, 6, 8, 9]  # Centered on 5, includes neighbors
}

puts "Finding correct formula for: #{test_data[:name]}"
puts "Transform: scale=#{test_data[:scale]}, translate=(#{test_data[:tx]}, #{test_data[:ty]})"
puts "Expected: Cell #{test_data[:expected_primary_cell]} dominant"
puts

# Test many formula variations
formulas = []

# Variations with different offset calculations
[-2, -1.5, -1, -0.5, 0, 0.5, 1, 1.5, 2].each do |factor|
  formulas << {
    name: "inv_tx = -tx/scale + #{factor}*canvas_cx",
    calc: ->(tx, ty, scale, cx, cy) {
      inv_scale = 1.0 / scale
      offset_x = factor * cx
      offset_y = factor * cy
      [-tx * inv_scale + offset_x, -ty * inv_scale + offset_y, inv_scale]
    }
  }
end

# Also test with canvas_cx/scale variations
[-1, -0.5, 0, 0.5, 1].each do |factor|
  formulas << {
    name: "inv_tx = -tx - #{factor}*canvas_cx/scale",
    calc: ->(tx, ty, scale, cx, cy) {
      inv_scale = 1.0 / scale
      offset_x = factor * cx / scale
      offset_y = factor * cy / scale
      [-tx - offset_x, -ty - offset_y, inv_scale]
    }
  }
end

best_match = nil
best_score = 0

formulas.each do |formula|
  inv_tx, inv_ty, inv_scale = formula[:calc].call(
    test_data[:tx], test_data[:ty], test_data[:scale], canvas_cx, canvas_cy
  )

  # Map canvas corners
  corners = [[0, 0], [canvas_w, 0], [0, canvas_h], [canvas_w, canvas_h]]
  orig_coords = corners.map { |cx, cy| [cx * inv_scale + inv_tx, cy * inv_scale + inv_ty] }

  min_x = [orig_coords.map(&:first).min, 0].max.floor
  max_x = [orig_coords.map(&:first).max, width].min.ceil
  min_y = [orig_coords.map(&:last).min, 0].max.floor
  max_y = [orig_coords.map(&:last).max, height].min.ceil

  next if max_x <= min_x || max_y <= min_y

  # Extract and check which cells
  extracted = grid.extract_area(min_x, min_y, max_x - min_x, max_y - min_y)
  resized = extracted.resize(canvas_w.to_f / extracted.width, vscale: canvas_h.to_f / extracted.height)

  # Sample center to identify primary cell
  center_value = resized.getpoint(canvas_cx.to_i, canvas_cy.to_i)[0]
  cell_num = (center_value / 28.0).round

  # Score based on how close to expected
  score = 0
  score += 10 if cell_num == test_data[:expected_primary_cell]
  score += test_data[:expected_cells].include?(cell_num) ? 5 : 0

  if score >= best_score
    best_score = score
    best_match = {
      formula: formula[:name],
      inv_tx: inv_tx,
      extraction: [min_x, min_y, max_x - min_x, max_y - min_y],
      cell_detected: cell_num,
      score: score
    }
  end

  if score >= 10
    puts "✓✓✓ #{formula[:name]}"
    puts "  inv_tx=#{inv_tx.round(2)}, Extraction: (#{min_x}, #{min_y}, #{max_x-min_x}, #{max_y-min_y})"
    puts "  Primary cell detected: #{cell_num} (expected #{test_data[:expected_primary_cell]})"
    puts "  SCORE: #{score}/15 ✓✓✓"
    puts
  end
end

if best_match
  puts "=" * 80
  puts "BEST MATCH (Score: #{best_match[:score]}/15):"
  puts "  Formula: #{best_match[:formula]}"
  puts "  inv_tx: #{best_match[:inv_tx].round(2)}"
  puts "  Extraction: #{best_match[:extraction].inspect}"
  puts "  Cell detected: #{best_match[:cell_detected]}"
  puts "=" * 80
end
