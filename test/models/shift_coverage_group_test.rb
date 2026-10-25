# frozen_string_literal: true

require "test_helper"

class ShiftCoverageGroupTest < ActiveSupport::TestCase
  setup do
    @position = Position.create!(title: "ZZ Probe Position", type: Position::TYPE_OTHER)
  end

  test "shift types come back in the order of their sort_index" do
    assert_equal %w[command echelon hq intercept], ShiftCoverageGroup.ordered.pluck(:slug)
  end

  # The fixture ids are hashed from the names, so the id order is not the
  # column order and only the sort_index can put these right.
  test "a shift type's posts come back in column order" do
    posts = shift_coverage_group(:command).shift_coverage_positions.to_a

    assert_equal Array(1..18), posts.map(&:sort_index)
    assert_equal %w[OOD DOOD RSL], posts.first(3).map(&:title)
    assert_equal "Burn", posts.last.title
  end

  # Written past the validations, so it is the index being tested: two admins
  # saving the same slug at once both pass a check made before either has saved.
  test "the database refuses a second shift type with the same slug" do
    twin = ShiftCoverageGroup.new(slug: "command", title: "Command Again",
                                  base_position_ids: [2], sort_index: 99)

    assert_raises(ActiveRecord::RecordNotUnique) { twin.save(validate: false) }
  end

  # ------------------------------------------------------ period positions

  # The report matches these against slot.position_id, and "19" never equals 19.
  test "period positions given as strings are stored once, as integers" do
    group = build_group(base_position_ids: [@position.id.to_s, @position.id.to_s, ""])
    group.save!

    assert_equal [@position.id], group.reload.base_position_ids
  end

  test "a junk id is refused rather than dropped" do
    group = build_group(base_position_ids: ["abc"])

    assert_not group.valid?
    assert_equal ["Period position \"abc\" is not a position id."], group.errors[:base_position_ids]
    assert_equal ["abc"], group.base_position_ids, "kept as sent, so the form can show what was refused"
  end

  test "an empty list is refused, whether it was sent empty, sent blank or never sent" do
    never_sent = ShiftCoverageGroup.new(slug: "probe", title: "Probe", sort_index: 99)

    [build_group(base_position_ids: []), build_group(base_position_ids: [""]),
     build_group(base_position_ids: nil), never_sent].each do |group|
      assert_not group.valid?
      assert_equal ["Choose at least one period position."], group.errors[:base_position_ids]
    end
  end

  # The boxes post in title order, so without this an untouched save of a list
  # stored in another order rewrites it and logs a change nobody made.
  test "period positions already stored keep their places when the same ones are sent again" do
    other = Position.create!(title: "AA Probe Position", type: Position::TYPE_OTHER)
    group = build_group(base_position_ids: [@position.id, other.id])
    group.save!

    group.base_position_ids = ["", other.id.to_s, @position.id.to_s]

    assert_not group.changed?
    group.base_position_ids = [other.id.to_s]
    assert_equal [other.id], group.base_position_ids, "an id unticked still goes"
  end

  test "an id that names no position is refused, and an inactive position is accepted" do
    ghost = build_group(base_position_ids: [999_999_999])

    assert_not ghost.valid?
    assert_equal ["Period position #999999999 does not exist."], ghost.errors[:base_position_ids]

    retired = Position.create!(title: "ZZ Retired", type: Position::TYPE_OTHER, active: false)
    assert build_group(base_position_ids: [retired.id]).valid?
  end

  # ----------------------------------------------------------------- slug

  test "a slug is lowercase words joined by single dashes" do
    invalid = "The slug may hold only lowercase letters, numbers and single dashes between them."

    ["Gerlach-Patrol", "a b", "-x", "x-"].each do |slug|
      group = build_group(slug:)

      assert_not group.valid?, slug.inspect
      assert_equal [invalid], group.errors[:slug], "the slug #{slug.inspect}"
    end
    ["gerlach-patrol-2", "all"].each { |slug| assert build_group(slug:).valid?, slug }
  end

  test "a slug is required, unique and no longer than forty characters" do
    assert_equal ["Enter a slug for the shift type."], errors_on(build_group(slug: ""), :slug)
    assert_equal ["Another shift type already uses that slug."], errors_on(build_group(slug: "command"), :slug)
    assert_equal ["The slug is too long. Use 40 characters or fewer."], errors_on(build_group(slug: "a" * 41), :slug)
  end

  test "a title is required, no longer than forty characters, and unique" do
    assert_equal ["Enter a title for the shift type."], errors_on(build_group(title: ""), :title)
    assert_equal ["The shift type title is too long. Use 40 characters or fewer."],
                 errors_on(build_group(title: "T" * 41), :title)
    # The report's menu names a shift type by its title alone. Trimmed, and
    # compared without case, so neither a stray space nor a capital makes a twin.
    [" Command ", "command"].each do |title|
      assert_equal ["Another shift type already uses that title."], errors_on(build_group(title:), :title), title
    end
  end

  # ----------------------------------------------------------------- order

  test "a shift type moves one place up or down the menu, and not past either end" do
    command, echelon, _hq, intercept = %i[command echelon hq intercept].map { |name| shift_coverage_group(name) }

    assert command.move("down")
    assert_equal %w[echelon command hq intercept], ShiftCoverageGroup.ordered.pluck(:slug)
    assert_equal [1, 2, 3, 4], ShiftCoverageGroup.ordered.pluck(:sort_index), "the line is renumbered"

    assert_not echelon.move("up"), "already first"
    assert_not intercept.move("down"), "already last"
    assert_not command.move("sideways")
    assert intercept.move("up")
    assert_equal %w[echelon command intercept hq], ShiftCoverageGroup.ordered.pluck(:slug)
  end

  test "a new shift type joins the end of the line" do
    assert_equal 8, ShiftCoverageGroup.new.next_sort_index
  end

  test "deleting a shift type deletes its posts, and the log names each one" do
    group = shift_coverage_group(:echelon)
    ActionLog.delete_all

    assert_difference({ "ShiftCoveragePosition.count" => -3, "ShiftCoverageGroup.count" => -1 }) do
      group.destroy!
    end

    assert_equal ["shift-coverage-position-delete"] * 3 + ["shift-coverage-group-delete"],
                 ActionLog.order(:id).pluck(:event)
  end

  private

  # A shift type that is valid as built, so a test names only what it is about.
  def build_group(**attributes)
    ShiftCoverageGroup.new({ slug: "probe", title: "Probe", sort_index: 99,
                             base_position_ids: [@position.id] }.merge(attributes))
  end

  def errors_on(group, attribute)
    group.valid?
    group.errors[attribute]
  end
end
