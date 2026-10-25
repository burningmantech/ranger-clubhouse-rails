# frozen_string_literal: true

require "test_helper"

# The live Shift Lead Report: who is signed in right now.
class OnDutyShiftLeadReportTest < ActiveSupport::TestCase
  include TrainingSlotTestHelper
  include PersonTestFactory
  include ActiveSupport::Testing::TimeHelpers

  YEAR = 2025
  NOW = Time.zone.local(YEAR, 8, 27, 14, 0, 0)

  setup do
    travel_to NOW
    Rails.cache.clear
    Current.reset

    @dirt = create_position(Position::DIRT, "Dirt", short_title: "Dirt")
    @green_dot = create_position(Position::DIRT_GREEN_DOT, "Dirt - Green Dot", short_title: "GD",
                                 on_sl_report: true)
    @ood = create_position(Position::OOD, "Operator on Duty", short_title: "OOD",
                           type: Position::TYPE_COMMAND)
    @intercept = create_position(Position::INTERCEPT, "Intercept", short_title: "Int")
  end

  teardown do
    Current.reset
    Rails.cache.clear
    travel_back
  end

  test "each roster draws from its own positions" do
    sign_in(create_person("Dusty"), @dirt)
    sign_in(create_person("Khaki"), @ood)
    sign_in(create_person("Cutter"), @intercept)

    result = report

    assert_predicate result, :on_duty?
    assert_equal ["Dusty"], result.dirt.map(&:callsign)
    assert_equal ["Khaki"], result.command.map(&:callsign)
    assert_equal ["Cutter"], result.special.map(&:callsign)
  end

  test "a Ranger who has signed out is off the report" do
    sign_in(create_person("Gone"), @dirt).update!(off_duty: NOW - 10.minutes,
                                                  additional_notes: "went home")

    assert_empty report.dirt
  end

  # A shift opened months ago and never closed is a data fault, not somebody
  # standing in the dust. Left unbounded it reads a duration in the thousands of
  # hours and, worse, counts toward the head count that decides whether a
  # position is short.
  test "a sign-in older than the lookback window is not on duty now" do
    sign_in(create_person("Forgotten"), @dirt, on_duty: NOW - 20.days)

    assert_empty report.dirt
  end

  test "a sign-in inside the lookback window still counts" do
    sign_in(create_person("Enduring"), @dirt, on_duty: NOW - 10.days)

    assert_equal ["Enduring"], report.dirt.map(&:callsign)
  end

  test "a stale sign-in cannot satisfy a position that is short" do
    create_slot(@green_dot, begins: NOW - 2.hours, ends: NOW + 4.hours, min: 1, max: 2)
    sign_in(create_person("Forgotten"), @green_dot, on_duty: NOW - 20.days)

    assert_equal 0, report.below_min.sole.count
    assert_equal 0, report.green_dot_total
  end

  test "a row carries when they signed in and how long they have been out" do
    sign_in(create_person("Dusty"), @dirt, on_duty: NOW - 90.minutes)

    row = report.dirt.sole

    assert_equal NOW - 90.minutes, row.on_duty
    assert_equal 90.minutes.to_i, row.duration
  end

  # Anyone on duty signed in at an HQ window, so they are on site whatever the
  # flag on their record still says.
  test "everyone on duty counts as on site" do
    person = create_person("Dusty")
    person.update!(on_site: false)
    sign_in(person, @dirt)

    assert report.dirt.sole.on_site
  end

  # Deliberately not person.years_as_ranger, which is materialised under a
  # stricter rule -- the two reports can print different numbers, and upstream
  # has the same split.
  test "years rangered counts the distinct years holding an entry" do
    person = create_person("Elder", years: [1999])
    past_entry(person, 2019)
    past_entry(person, 2021)
    past_entry(person, 2021)
    sign_in(person, @dirt)

    assert_equal 3, report.dirt.sole.years
  end

  test "echelon entries are left out of the years count" do
    person = create_person("Contributor", years: [])
    past_entry(person, 2019, is_echelon: true)
    sign_in(person, @dirt)

    assert_equal 1, report.dirt.sole.years
  end

  # The head count is per position, not per slot: what a shift lead needs to
  # know is how many Green Dots are out, not how many are out on one slot.
  test "a position running now with no one on duty is below minimum" do
    create_slot(@green_dot, begins: NOW - 2.hours, ends: NOW + 4.hours, min: 2, max: 2)

    row = report.below_min.sole

    assert_equal "Dirt - Green Dot", row.title
    assert_equal 0, row.count
  end

  test "a position with enough people on duty is not listed" do
    create_slot(@green_dot, begins: NOW - 2.hours, ends: NOW + 4.hours, min: 1, max: 2)
    sign_in(create_person("Verde"), @green_dot)

    assert_predicate report, :fully_staffed?
  end

  test "a shift that has not started yet is not counted as short" do
    create_slot(@dirt, begins: NOW + 1.hour, ends: NOW + 7.hours, min: 5, max: 5)

    assert_predicate report, :fully_staffed?
  end

  # The head count is per position, so the rows must be too -- otherwise two
  # overlapping slots print one shortfall twice and every total built from the
  # list counts it twice.
  test "two overlapping slots of one position are one shortfall" do
    create_slot(@green_dot, begins: NOW - 2.hours, ends: NOW + 4.hours, min: 2, max: 2)
    create_slot(@green_dot, begins: NOW - 1.hour, ends: NOW + 6.hours, min: 2, max: 2)

    row = report.below_min.sole

    assert_equal "Dirt - Green Dot", row.title
    # The widest window across the position's running slots.
    assert_equal NOW - 2.hours, row.begins
    assert_equal NOW + 6.hours, row.ends
  end

  # Upstream's live loader has no active filter at all, and the positions list
  # decides the chips as well as the column.
  test "a deactivated position still labels and classifies a Ranger on duty" do
    person = create_person("Wrench")
    troubleshooter = create_position(Position::TROUBLESHOOTER, "Troubleshooter", short_title: "TS",
                                     on_sl_report: true)
    troubleshooter.update!(active: false)
    PersonPosition.create!(person:, position: troubleshooter)
    sign_in(person, @dirt)

    row = report.dirt.sole

    assert_includes row.positions, "TS"
    assert row.troubleshooter
  end

  test "the Green Dot head count reads off who is signed in" do
    her = create_person("Verde")
    her.update!(gender_identity: Gender::GENDER_FEMALE)
    sign_in(her, @green_dot)
    sign_in(create_person("Esmeralda"), @green_dot)

    result = report

    assert_equal 2, result.green_dot_total
    assert_equal 1, result.green_dot_females
  end

  private

  def report = OnDutyShiftLeadReport.execute

  def create_position(id, title, short_title: nil, type: Position::TYPE_FRONTLINE, on_sl_report: nil)
    Position.create!(id:, title:, short_title:, type:, active: true, on_sl_report:)
  end

  def sign_in(person, position, on_duty: NOW - 1.hour)
    Timesheet.create!(person:, position:, on_duty:, additional_notes: "signed in for the test")
  end

  def past_entry(person, year, is_echelon: false)
    Timesheet.create!(person:, position: @dirt, is_echelon:,
                      on_duty: Time.zone.local(year, 8, 27, 12, 0, 0),
                      off_duty: Time.zone.local(year, 8, 27, 18, 0, 0),
                      additional_notes: "a past shift")
  end
end
