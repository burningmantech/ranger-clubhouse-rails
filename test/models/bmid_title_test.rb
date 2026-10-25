# frozen_string_literal: true

require "test_helper"

# The badge title list: what the database insists on, said in Ruby so the form
# can show it rather than throwing a constraint error.
class BmidTitleTest < ActiveSupport::TestCase
  include TicketingTestHelper

  YEAR = 2026

  setup do
    BmidTitle.delete_all
  end

  test "a title needs text, a line, a preference, and a position" do
    title = BmidTitle.new

    assert_not title.valid?
    assert_equal %i[position title title_line sort_index].sort, title.errors.attribute_names.sort
  end

  test "the line must be one of the three the badge prints" do
    assert build_title(title_line: 3).valid?

    title = build_title(title_line: 4)
    assert_not title.valid?
    assert_equal ["Title line must be 1, 2, or 3."], title.errors[:title_line]
  end

  test "the title fits the badge column" do
    assert_not build_title(title: "x" * 65).valid?
    assert build_title(title: "x" * 64).valid?
  end

  test "a position earns at most one title per line" do
    build_title.save!

    duplicate = build_title(title: "Something Else")
    assert_not duplicate.valid?
    assert_equal ["This position already earns a title on this line."], duplicate.errors[:position_id]

    # The same position on a different line is the whole point of three lines.
    assert build_title(title_line: 2).valid?
  end

  test "the ordered scope reads line first, then preference" do
    third = build_title(title_line: 3, sort_index: 1, title: "007").tap(&:save!)
    second = build_title(sort_index: 2, title: "Department Manager").tap(&:save!)
    first = build_title(sort_index: 1, title: "Shift Lead",
                        position: position_for(Position::RSC_SHIFT_LEAD)).tap(&:save!)

    assert_equal [first, second, third], BmidTitle.ordered.to_a
  end

  test "a title names the badge column it prints in" do
    assert_equal "title2", build_title(title_line: 2).bmid_column
  end

  # --- reordering a line ----------------------------------------------------

  test "moving a title down swaps it with the one below" do
    first, second, third = ordered_line

    assert second.move!(BmidTitle::MOVE_DOWN)
    assert_equal [first, third, second], BmidTitle.ordered.to_a
    assert_equal [1, 2, 3], BmidTitle.ordered.map(&:sort_index)
  end

  test "moving a title up swaps it with the one above" do
    first, second, third = ordered_line

    assert third.move!(BmidTitle::MOVE_UP)
    assert_equal [first, third, second], BmidTitle.ordered.to_a
  end

  test "a title at the end of its line does not move" do
    first, _second, third = ordered_line

    assert_not first.move!(BmidTitle::MOVE_UP)
    assert_not third.move!(BmidTitle::MOVE_DOWN)
    assert_equal [1, 2, 3], BmidTitle.ordered.map(&:sort_index)
  end

  # Equal numbers are legal in the table, and swapping two of them would move
  # nothing -- hence renumbering the line rather than trading sort_index values.
  test "a line whose titles all share a number still reorders" do
    3.times { |index| build_title(sort_index: 1, title: "Title #{index}", position: position_for(index + 40)).save! }
    last = BmidTitle.ordered.last

    assert last.move!(BmidTitle::MOVE_UP)
    assert_equal ["Title 0", "Title 2", "Title 1"], BmidTitle.ordered.map(&:title)
    assert_equal [1, 2, 3], BmidTitle.ordered.map(&:sort_index)
  end

  test "moving a title leaves the other lines alone" do
    other = build_title(title_line: 2, sort_index: 9, title: "Elsewhere").tap(&:save!)
    _first, second, = ordered_line

    second.move!(BmidTitle::MOVE_DOWN)

    assert_equal 9, other.reload.sort_index
  end

  private

  # Three titles on line 1, numbered 1, 2, 3.
  def ordered_line
    ["Shift Lead", "Department Manager", "Operations Manager"].each_with_index.map do |title, index|
      build_title(title:, sort_index: index + 1, position: position_for(index + 30)).tap(&:save!)
    end
  end

  def build_title(**attributes)
    BmidTitle.new({ title: "Shift Lead", title_line: 1, sort_index: 1,
                    position: position_for(Position::OOD) }.merge(attributes))
  end
end
