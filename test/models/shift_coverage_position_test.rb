# frozen_string_literal: true

require "test_helper"

class ShiftCoveragePositionTest < ActiveSupport::TestCase
  setup do
    @troubleshooter = Position.create!(title: "Troubleshooter", type: Position::TYPE_OTHER)
    @mentee = Position.create!(title: "Troubleshooter Mentee", type: Position::TYPE_OTHER)
  end

  test "a post reads its positions and the labels printed after their callsigns" do
    post = shift_coverage_position(:command_ts)

    assert_equal [91, 127, 147], post.position_id_list
    assert_equal({ 127 => "Mentee", 147 => "TSLEAL" }, post.labels_by_position)
  end

  # The report matches these against slot.position_id, and "91" never equals 91.
  # Written past the validations, so a later rule that the positions must exist
  # does not turn this into a test of Position rows.
  test "ids are still integers after they are written and read back" do
    post = shift_coverage_position(:echelon_lead)

    post.update_columns(position_ids: [[91], [127, "Mentee"]])

    assert_equal [[91], [127, "Mentee"]], post.reload.position_ids
  end

  # ---------------------------------------------------------------- the rows

  test "rows are paired into entries: a blank row dropped, a lone label and a junk id kept" do
    assert_equal [[91], [127, "Mentee"]],
                 ShiftCoveragePosition.entries_from_rows(["91", "127", ""], ["", " Mentee ", ""])
    assert_equal [["", "Mentee"]], ShiftCoveragePosition.entries_from_rows([""], ["Mentee"]),
                 "kept, so the validation can name it"
    assert_equal [["abc"]], ShiftCoveragePosition.entries_from_rows(["abc"], [""]), "kept as sent, so it is refused"
    assert_empty ShiftCoveragePosition.entries_from_rows(nil, nil)
  end

  # ------------------------------------------------------------ validations

  test "a post with a title, positions that exist and a choice of what it shows is valid" do
    assert build_post.valid?
    assert build_post(position_ids: [[@troubleshooter.id], [@mentee.id, "Mentee"]], count_only: true).valid?
  end

  test "a label with no position is refused with its message, and the error carries its row" do
    post = build_post(position_ids: [[@troubleshooter.id], ["", "Mentee"]])

    assert_not post.valid?
    assert_equal ["The label \"Mentee\" needs a position beside it."], post.errors[:position_ids]
    assert_equal [1], post.errors.details[:position_ids].pluck(:row)
  end

  test "the same position twice is refused, by name, on the second row" do
    post = build_post(position_ids: [[@troubleshooter.id], [@mentee.id], [@troubleshooter.id, "Again"]])

    assert_not post.valid?
    assert_equal ["Troubleshooter is listed twice. List each position once."], post.errors[:position_ids]
    assert_equal [2], post.errors.details[:position_ids].pluck(:row)
  end

  test "a label of more than twenty characters is refused" do
    post = build_post(position_ids: [[@troubleshooter.id, "A label that runs on and on"]])

    assert_not post.valid?
    assert_equal ["The label \"A label that runs on a...\" is too long. Use 20 characters or fewer."],
                 post.errors[:position_ids]
  end

  test "an entry that is no position, or names none that exists, is refused" do
    {
      "abc" => "Position \"abc\" is not a position id.",
      [] => "Position [] is not a position id.",
      [1, 2, 3] => "Position [1, 2, 3] is not a position id.",
      ["abc"] => "Position \"abc\" is not a position id.",
      [999_999_999] => "Position #999999999 does not exist."
    }.each do |entry, message|
      post = build_post(position_ids: [entry])

      assert_not post.valid?, entry.inspect
      assert_equal [message], post.errors[:position_ids], "the entry #{entry.inspect}"
    end
  end

  test "a list that is empty, blank or missing is refused" do
    [[], nil].each do |list|
      post = build_post(position_ids: list)

      assert_not post.valid?
      assert_equal ["Choose at least one position for the post."], post.errors[:position_ids]
    end
  end

  test "whether a post shows a headcount or callsigns has to be chosen" do
    post = build_post(count_only: nil)

    assert_not post.valid?
    assert_equal ["Choose whether the post shows a headcount or callsigns."], post.errors[:count_only]
  end

  test "a title is required, no longer than twenty characters, and unique within its shift type" do
    assert_equal ["Enter a title for the post."], errors_on(build_post(title: ""), :title)
    assert_equal ["The post title is too long. Use 20 characters or fewer."], errors_on(build_post(title: "T" * 21), :title)
    # Compared without case, and trimmed, so neither "ood" nor " OOD" makes a
    # second column headed OOD.
    ["OOD", "ood", " OOD "].each do |title|
      assert_equal ["This shift type already has a post with that title."],
                   errors_on(build_post(shift_coverage_group: shift_coverage_group(:command), title:), :title), title
    end
    assert build_post(title: "OOD").valid?, "the same title in another shift type is fine"
  end

  test "a post has to belong to a shift type" do
    post = build_post(shift_coverage_group: nil)

    assert_not post.valid?
    assert_equal ["Choose the shift type this post belongs to."], post.errors[:shift_coverage_group]
  end

  # ------------------------------------------------------------------ order

  test "a post moves up and down its own shift type, and leaves the others alone" do
    lead, field, training = %i[echelon_lead echelon_field echelon_lead_training].map { |name| shift_coverage_position(name) }

    assert_not lead.move("up"), "already first"
    assert field.move("up")
    assert_equal ["Echelon Field", "Echelon Lead", "Lead Training"], shift_coverage_group(:echelon).shift_coverage_positions.map(&:title)
    assert_not training.move("down"), "already last"
    assert_equal Array(1..18), shift_coverage_group(:command).shift_coverage_positions.map(&:sort_index)
  end

  test "a new post joins the end of its own shift type's line" do
    assert_equal 19, build_post(shift_coverage_group: shift_coverage_group(:command)).next_sort_index
    assert_equal 4, build_post.next_sort_index
  end

  private

  # A post that is valid as built, in Echelon, so a test names only what it is about.
  def build_post(**attributes)
    ShiftCoveragePosition.new({ shift_coverage_group: shift_coverage_group(:echelon), title: "Probe",
                                count_only: false, sort_index: 99,
                                position_ids: [[@troubleshooter.id]] }.merge(attributes))
  end

  def errors_on(post, attribute)
    post.valid?
    post.errors[attribute]
  end
end
