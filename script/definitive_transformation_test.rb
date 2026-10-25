#!/usr/bin/env ruby
# Definitive test to identify correct CropperJS transformation formula
# Uses actual user transform values to test extraction accuracy
# Fails hard if results don't match expected regions

require "vips"

# Test image: 750×1125 with 3×3 grid (each cell 250×375)
width = 750
height = 1125
cell_w = 250
cell_h = 375

# Create grid with unique values per cell
cells = 9.times.map { |i| Vips::Image.black(cell_w, cell_h) + ((i + 1) * 28) }
row1 = cells[0].join(cells[1], :horizontal).join(cells[2], :horizontal)
row2 = cells[3].join(cells[4], :horizontal).join(cells[5], :horizontal)
row3 = cells[6].join(cells[7], :horizontal).join(cells[8], :horizontal)
grid = row1.join(row2, :vertical).join(row3, :vertical)

puts "Grid Layout (750×1125):"
puts "  Cell 1(28)  Cell 2(56)  Cell 3(84)   ← TOP"
puts "  Cell 4(112) Cell 5(140) Cell 6(168)  ← MIDDLE"
puts "  Cell 7(196) Cell 8(224) Cell 9(252)  ← BOTTOM"
puts

# Actual transform from user's test (centered face)
scale_x = 0.7086244000000003
scale_y = 0.7086244000000003
translate_x = -186.71875
translate_y = -207.453125

puts "User's centered face crop:"
puts "  Scale: #{scale_x}"
puts "  Translate: (#{translate_x}, #{translate_y})"
puts "  User says: Face centered in canvas, but result shows bottom-right"
puts

# Test current formula
inv_scale = 1.0 / scale_x
inv_tx = -translate_x * inv_scale
inv_ty = -translate_y * inv_scale

cx, cy = 0, 0  # Canvas top-left
ox = cx * inv_scale + inv_tx
oy = cy * inv_scale + inv_ty

puts "Current formula: ox = cx / scale - translate / scale"
puts "  Canvas (0,0) → Original (#{ox.round(1)}, #{oy.round(1)})"

# Which cell is this?
cell_x = (ox / cell_w).floor + 1
cell_y = (oy / cell_h).floor + 1
cell_num = (cell_y - 1) * 3 + cell_x

if cell_num.between?(1, 9)
  puts "  This is in CELL #{cell_num}"

  case cell_num
  when 1
    puts "  → TOP-LEFT cell ✓ If user positioned at top-left"
  when 5
    puts "  → CENTER cell ✓ If user positioned centered"
  when 9
    puts "  → BOTTOM-RIGHT cell ✓ If user positioned at bottom-right"
  else
    puts "  → Offset cell (not a corner or center)"
  end
else
  puts "  → OUTSIDE grid bounds ❌"
end

puts
puts "=" * 80
puts "CRITICAL QUESTION TO RESOLVE:"
puts "Where is the person's FACE actually located in the original 750×1125 photo?"
puts "  - If face is centered: near pixel (375, 562) = Cell 5"
puts "  - If face is top-left: near pixel (125, 187) = Cell 1"
puts "  - If face is offset: specify approximate pixel location"
puts
puts "Once we know actual face location, we can verify if extraction is correct!"
puts "=" * 80
