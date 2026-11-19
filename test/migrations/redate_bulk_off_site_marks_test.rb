# frozen_string_literal: true

require "test_helper"
require Rails.root.join("db/migrate/20261118000002_redate_bulk_off_site_marks.rb")

# Labor Day 2025 was September 1: the window for a stay begun that year runs
# from October 2, 2025 through April 1, 2026.
class RedateBulkOffSiteMarksTest < ActiveSupport::TestCase
  MIGRATION = RedateBulkOffSiteMarks

  ARRIVED = Time.zone.local(2025, 8, 22, 14, 0)
  RESET = Time.zone.local(2026, 2, 10, 9, 0)
  LAST_SIGN_OUT = Time.zone.local(2025, 9, 1, 18, 0)

  setup do
    Current.reset
    @ranger = person(:active_ranger)
  end

  teardown { Current.reset }

  test "a reset's mark moves to the last sign-out or asset return of the stay and becomes automatic" do
    mark(@ranger, PersonOnSite::ON_SITE, ARRIVED)
    reset = mark(@ranger, PersonOnSite::OFF_SITE, RESET)
    timesheet(@ranger, LAST_SIGN_OUT - 2.days)
    timesheet(@ranger, LAST_SIGN_OUT)
    returner = person(:retired_ranger)
    mark(returner, PersonOnSite::ON_SITE, ARRIVED)
    returned = mark(returner, PersonOnSite::OFF_SITE, RESET)
    timesheet(returner, LAST_SIGN_OUT)
    asset_loan(returner, ARRIVED + 1.hour, LAST_SIGN_OUT + 3.hours)

    assert_equal [2, 0], redate

    assert_equal [LAST_SIGN_OUT, PersonOnSite::AUTOMATIC], reset.reload.values_at(:created_at, :reason)
    assert_equal [LAST_SIGN_OUT + 3.hours, PersonOnSite::AUTOMATIC], returned.reload.values_at(:created_at, :reason)
    assert_equal [0, 0], redate, "a second run finds nothing left to do"
  end

  # Marks made at the window, during the event or at the next one, are no reset's.
  test "a mark within a month of Labor Day, or more than seven months after it, is left alone" do
    mark(@ranger, PersonOnSite::ON_SITE, ARRIVED)
    timesheet(@ranger, LAST_SIGN_OUT)
    at_the_window = mark(@ranger, PersonOnSite::OFF_SITE, Time.zone.local(2025, 10, 1, 12, 0))
    late = person(:retired_ranger)
    mark(late, PersonOnSite::ON_SITE, ARRIVED)
    timesheet(late, LAST_SIGN_OUT)
    next_summer = mark(late, PersonOnSite::OFF_SITE, Time.zone.local(2026, 4, 2, 12, 0))

    assert_equal [0, 0], redate

    assert_equal [Time.zone.local(2025, 10, 1, 12, 0), PersonOnSite::MANUAL],
                 at_the_window.reload.values_at(:created_at, :reason)
    assert_equal [Time.zone.local(2026, 4, 2, 12, 0), PersonOnSite::MANUAL],
                 next_summer.reload.values_at(:created_at, :reason)
  end

  test "the window's two edges: one month and a day is in, seven months to the day is in" do
    mark(@ranger, PersonOnSite::ON_SITE, ARRIVED)
    timesheet(@ranger, LAST_SIGN_OUT)
    first_day = mark(@ranger, PersonOnSite::OFF_SITE, Time.zone.local(2025, 10, 2, 12, 0))
    other = person(:retired_ranger)
    mark(other, PersonOnSite::ON_SITE, ARRIVED)
    timesheet(other, LAST_SIGN_OUT)
    last_day = mark(other, PersonOnSite::OFF_SITE, Time.zone.local(2026, 4, 1, 12, 0))

    assert_equal [2, 0], redate

    assert_equal [LAST_SIGN_OUT, LAST_SIGN_OUT], [first_day, last_day].map { it.reload.created_at }
  end

  # A date outside the stay would put the off-site mark ahead of the on-site
  # mark it closes, or after the day it is known to have been made by.
  test "a mark with no activity inside its stay keeps its date and stays manual" do
    idle = @ranger
    mark(idle, PersonOnSite::ON_SITE, ARRIVED)
    untouched = mark(idle, PersonOnSite::OFF_SITE, RESET)
    early = person(:retired_ranger)
    timesheet(early, ARRIVED - 1.day)
    mark(early, PersonOnSite::ON_SITE, ARRIVED)
    before_arrival = mark(early, PersonOnSite::OFF_SITE, RESET)
    timesheet(early, Time.zone.local(2025, 12, 20, 16, 0), year_end: true)

    assert_equal [0, 2], redate

    [untouched, before_arrival].each do |row|
      assert_equal [RESET, PersonOnSite::MANUAL], row.reload.values_at(:created_at, :reason)
    end
  end

  # Only a mark that closes a stay has a stay to be dated from.
  test "an off-site mark with no on-site mark before it is left alone" do
    orphan = mark(@ranger, PersonOnSite::OFF_SITE, RESET)
    timesheet(@ranger, LAST_SIGN_OUT)

    assert_equal [0, 0], redate
    assert_equal RESET, orphan.reload.created_at
  end

  private

  def redate = MIGRATION.new.send(:redate_marks)

  def mark(person, action, created_at)
    PersonOnSite.create!(person:, action:, created_at:)
  end

  # year_end: an entry from the stay's year that ends after the reset's mark
  # would be dated wrongly -- here it only starts in that year.
  def timesheet(person, off_duty, year_end: false)
    off_duty = RESET + 1.day if year_end
    on_duty = year_end ? Time.zone.local(2025, 12, 31, 20, 0) : off_duty - 6.hours
    Timesheet.new(person:, position: positions(:ood_position), on_duty:, off_duty:).save!(validate: false)
  end

  def asset_loan(person, checked_out, checked_in)
    PersonAsset.create!(person:, asset: asset(:radio_current_year), checked_out:, checked_in:)
  end
end
