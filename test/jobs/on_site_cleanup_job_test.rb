# frozen_string_literal: true

require "test_helper"

class OnSiteCleanupJobTest < ActiveSupport::TestCase
  # Labor Day 2026. The job wakes at 04:00 on each of September 6-14.
  LABOR_DAY = Date.new(2026, 9, 7)

  setup do
    Current.reset
    # Not left to Current.reset: person is a plain accessor, which reset leaves alone.
    Current.person = nil
    @ranger = person(:active_ranger)
  end

  teardown { Current.reset }

  test "it runs the cleanup on the Saturday, Sunday and Monday after Labor Day, and on no other morning" do
    ran = (-1..8).select do |days|
      @ranger.update_columns(on_site: true)
      travel_to (LABOR_DAY + days).in_time_zone.change(hour: 4) do
        OnSiteCleanupJob.perform_now
      end
      !@ranger.reload.on_site
    end

    assert_equal [5, 6, 7], ran
    assert_equal %w[Saturday Sunday Monday], ran.map { (LABOR_DAY + it).strftime("%A") }
  end

  test "its marks are automatic and name no one" do
    @ranger.update_columns(on_site: true)

    travel_to (LABOR_DAY + 5).in_time_zone.change(hour: 4) do
      OnSiteCleanupJob.perform_now
    end

    row = PersonOnSite.history_for(@ranger).first
    assert_equal [PersonOnSite::OFF_SITE, PersonOnSite::AUTOMATIC, nil],
                 [row.action, row.reason, row.creator_person_id]
  end

  # 2025: Labor Day is September 1, so the Saturday after it is the 6th.
  # 2026: Labor Day is the 7th, so the Monday after it is the 14th.
  test "the schedule's dates cover the three days in the earliest and the latest year" do
    [2025, 2026].each do |year|
      labor_day = EventDate.first_monday_of_september(year).to_date
      days = OnSiteCleanupJob::DAYS_AFTER_LABOR_DAY.map { (labor_day + it).day }
      assert days.all? { (6..14).cover?(it) }, "#{year}: #{days.inspect}"
    end
  end
end
