# frozen_string_literal: true

require "test_helper"

# Set BMID Titles: who the preview covers, which title each line proposes, and
# what the commit writes.
#
# The candidate sweep reads whole tables, so every test starts from empty ones
# and builds exactly the people it needs.
class BmidTitleAssignmentTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers
  include TicketingTestHelper

  YEAR = 2026

  setup do
    travel_to Time.zone.local(YEAR, 4, 8, 12, 0, 0)
    Current.reset
    Bmid.delete_all
    BmidTitle.delete_all
    AccessDocument.delete_all
    PersonSlot.delete_all
    Slot.delete_all
    PersonPosition.delete_all

    @shift_lead = badge_title(Position::RSC_SHIFT_LEAD, line: 1, sort: 1, title: "Shift Lead")
    @ood = badge_title(Position::OOD, line: 1, sort: 4, title: "Officer of the Day")
    @double_oh = badge_title(Position::DOUBLE_OH_7, line: 3, sort: 1, title: "007")

    @ranger = person(:active_ranger)
  end

  teardown do
    Current.reset
    travel_back
  end

  # --- who the preview covers -----------------------------------------------

  test "a qualified holder is previewed with the title their position earns" do
    hold(@ranger, Position::RSC_SHIFT_LEAD)
    qualify(@ranger)

    row = only_row

    assert_equal @ranger.id, row.person_id
    assert_equal "Shift Lead", row.proposed[1]
    assert_nil row.proposed[2]
    assert_nil row.proposed[3]
    assert row.new_badge?, "the badge does not exist yet"
  end

  test "a holder who has not earned a printed badge is left out" do
    hold(@ranger, Position::RSC_SHIFT_LEAD)

    assert_empty BmidTitleAssignment.preview(YEAR)
  end

  test "a holder who has left the Rangers is left out" do
    hold(@ranger, Position::RSC_SHIFT_LEAD)
    qualify(@ranger)
    @ranger.update_columns(status: Person::RESIGNED)

    assert_empty BmidTitleAssignment.preview(YEAR)
  end

  test "someone holding no title-earning position is left out" do
    hold(@ranger, Position::DIRT)
    qualify(@ranger)

    assert_empty BmidTitleAssignment.preview(YEAR)
  end

  test "an Echelon volunteer qualifies on a shift sign-up rather than a ticket" do
    echelon = person(:echelon_ranger)
    hold(echelon, Position::RSC_SHIFT_LEAD)
    sign_up(echelon, slot_for(Position::DIRT))

    assert_equal [echelon.id], BmidTitleAssignment.preview(YEAR).map(&:person_id)
  end

  test "nothing is previewed when no titles are defined" do
    BmidTitle.delete_all
    hold(@ranger, Position::RSC_SHIFT_LEAD)
    qualify(@ranger)

    assert_empty BmidTitleAssignment.preview(YEAR)
  end

  # --- which title a line proposes ------------------------------------------

  test "the lowest sort index wins when a line has more than one holder" do
    hold(@ranger, Position::OOD)
    hold(@ranger, Position::RSC_SHIFT_LEAD)
    qualify(@ranger)

    assert_equal "Shift Lead", only_row.proposed[1]

    # Flip the preference and the other title takes the line.
    @ood.update!(sort_index: 0)

    assert_equal "Officer of the Day", only_row.proposed[1]
  end

  test "a line no position feeds keeps what the badge already says" do
    hold(@ranger, Position::RSC_SHIFT_LEAD)
    qualify(@ranger)
    badge_for(@ranger, title1: "Stale", title2: "Keep Me")

    row = only_row

    assert_equal "Shift Lead", row.proposed[1], "an earned line is overwritten"
    assert_equal "Keep Me", row.proposed[2], "an unearned line is left alone"
  end

  # --- the commit -----------------------------------------------------------

  test "applying creates the badge and writes the earned titles" do
    hold(@ranger, Position::RSC_SHIFT_LEAD)
    hold(@ranger, Position::DOUBLE_OH_7)
    qualify(@ranger)

    changed = BmidTitleAssignment.apply(YEAR, {})

    assert_equal 1, changed.size
    badge = Bmid.find_for_person_year(@ranger.id, YEAR)
    assert_equal "Shift Lead", badge.title1
    assert_nil badge.title2
    assert_equal "007", badge.title3
    assert_equal Bmid::IN_PREP, badge.status
  end

  test "a submitted title overrules the one the position earns" do
    hold(@ranger, Position::RSC_SHIFT_LEAD)
    qualify(@ranger)

    BmidTitleAssignment.apply(YEAR, { @ranger.id => { 1 => "Khaki", 2 => "Green Dot" } })

    badge = Bmid.find_for_person_year(@ranger.id, YEAR)
    assert_equal "Khaki", badge.title1
    assert_equal "Green Dot", badge.title2
  end

  test "a blanked line clears the title the badge was carrying" do
    hold(@ranger, Position::RSC_SHIFT_LEAD)
    qualify(@ranger)
    badge_for(@ranger, title1: "Shift Lead")

    BmidTitleAssignment.apply(YEAR, { @ranger.id => { 1 => nil } })

    assert_nil Bmid.find_for_person_year(@ranger.id, YEAR).title1
  end

  test "a badge that would say nothing at all is not created" do
    hold(@ranger, Position::RSC_SHIFT_LEAD)
    qualify(@ranger)

    assert_empty BmidTitleAssignment.apply(YEAR, { @ranger.id => { 1 => nil } })
    assert_nil Bmid.find_for_person_year(@ranger.id, YEAR)
  end

  test "a badge that already says the right thing is left untouched" do
    hold(@ranger, Position::RSC_SHIFT_LEAD)
    qualify(@ranger)
    badge = badge_for(@ranger, title1: "Shift Lead")
    before = badge.updated_at

    assert_empty BmidTitleAssignment.apply(YEAR, {})
    assert_equal before.to_i, badge.reload.updated_at.to_i
  end

  test "a submission for someone the preview does not cover is ignored" do
    stranger = person(:inactive_ranger)

    assert_empty BmidTitleAssignment.apply(YEAR, { stranger.id => { 1 => "Sneaky" } })
    assert_nil Bmid.find_for_person_year(stranger.id, YEAR)
  end

  test "the change is logged against the badge with the run as its reason" do
    hold(@ranger, Position::RSC_SHIFT_LEAD)
    qualify(@ranger)

    BmidTitleAssignment.apply(YEAR, {})

    log = ActionLog.where(event: "bmid-create").last
    assert_not_nil log
    assert_equal BmidTitleAssignment::AUDIT_REASON, log.message
    assert_equal @ranger.id, log.target_person_id
  end

  private

  def badge_title(position_id, line:, sort:, title:)
    BmidTitle.create!(position: position_for(position_id), title_line: line,
                      sort_index: sort, title:)
  end

  def hold(holder, position_id)
    PersonPosition.create!(person: holder, position: position_for(position_id))
  end

  # The claimed ticket arm of Bmid#not_qualified_to_print?.
  def qualify(holder)
    document(holder, type: AccessDocument::SPT, status: AccessDocument::CLAIMED)
  end

  def badge_for(holder, **titles)
    Bmid.create!(person: holder, year: YEAR, status: Bmid::IN_PREP, **titles)
  end

  def only_row
    rows = BmidTitleAssignment.preview(YEAR)
    assert_equal 1, rows.size, "expected exactly one previewed badge"
    rows.first
  end
end
