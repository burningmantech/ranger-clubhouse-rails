# frozen_string_literal: true

require "test_helper"

# The parts the controller test cannot reach. The credit arithmetic and the
# visibility scope are shared with TimesheetByCallsignReport and tested there;
# what is this report's own is how the year is grouped and ordered.
class TimesheetByPositionReportTest < ActiveSupport::TestCase
  include TimesheetAdminTestHelper # ensure_role / grant_role

  # A year the timesheet fixtures leave alone -- they carry 2023, 2024, 2025.
  YEAR = 2022

  setup do
    Rails.cache.clear
    Current.reset

    @position = positions(:ood_position)
    @person = person(:active_ranger)

    ensure_role(Role::ADMIN, "Admin")
    @viewer = person(:echelon_ranger)
    grant_role(@viewer, Role::ADMIN)
  end

  teardown do
    Current.reset
    Rails.cache.clear
  end

  def create_timesheet(on_duty:, hours: 3, position: @position, person: @person)
    Timesheet.create!(person:, position:, on_duty:, off_duty: on_duty + hours.hours,
                      additional_notes: "test shift")
  end

  def august(day) = Time.zone.local(YEAR, 8, day, 12, 0, 0)

  # Upstream sorts with strcasecmp, so "alpha" sits with the A's rather than
  # after every capitalized title.
  test "the index sorts position titles case-insensitively" do
    titles = ["zebra wrangler", "Alpha", "mentor"]
    # Not named `positions` -- that would shadow the fixture accessor of the
    # same name for the rest of the test.
    subjects = [positions(:ood_position), positions(:council_manager),
                positions(:khaki_supervisor)]
    subjects.each_with_index do |position, index|
      position.update_columns(title: titles[index])
      create_timesheet(on_duty: august(25), position:)
    end

    index = TimesheetByPositionReport.summary(year: YEAR, viewer: @viewer).positions
    ordered = index.select { |row| titles.include?(row.title) }.map(&:title)

    assert_equal ["Alpha", "mentor", "zebra wrangler"], ordered
  end

  # One row per position, not per entry: the same ranger rangering a position
  # twice is one ranger.
  test "the index counts entries and rangers separately" do
    create_timesheet(on_duty: august(25), hours: 3)
    create_timesheet(on_duty: august(26), hours: 2)
    create_timesheet(on_duty: august(27), hours: 1, person: person(:retired_ranger))

    row = TimesheetByPositionReport.summary(year: YEAR, viewer: @viewer)
                                   .positions.find { |p| p.position_id == @position.id }

    assert_equal 3, row.entry_count
    assert_equal 2, row.people_count
    assert_equal 6.hours.to_i, row.total_duration
  end

  test "one position's entries come back oldest first" do
    create_timesheet(on_duty: august(27))
    create_timesheet(on_duty: august(25))
    create_timesheet(on_duty: august(26))

    detail = TimesheetByPositionReport.position(year: YEAR, position_id: @position.id,
                                                viewer: @viewer)

    assert_equal [25, 26, 27], detail.entries.map { |entry| entry.on_duty.day }
  end
end
