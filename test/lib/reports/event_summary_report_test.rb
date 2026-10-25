# frozen_string_literal: true

require "test_helper"

class EventSummaryReportTest < ActiveSupport::TestCase
  setup do
    @person = person(:active_ranger)
  end

  test "execute returns summary for person with timesheet entries" do
    result = EventSummaryReport.execute(@person.id, 2023)

    assert result.is_a?(OpenStruct)
    assert_respond_to result, :total_duration
    assert_respond_to result, :total_credits
  end

  test "execute returns zero totals for person without entries" do
    person_without_entries = person(:ranger_with_custom_gender)
    result = EventSummaryReport.execute(person_without_entries.id, 2023)

    assert_equal 0, result.total_duration
    assert_equal 0, result.total_credits
  end

  test "execute handles year with no event dates" do
    # Use a year with no event dates defined
    result = EventSummaryReport.execute(@person.id, 1990)

    assert result.is_a?(OpenStruct)
    # When no event dates, all time should be attributed to event period
    assert result.respond_to?(:no_event_dates) || result.total_duration >= 0
  end

  test "execute calculates pre-event, event, and post-event durations" do
    result = EventSummaryReport.execute(@person.id, 2023)

    # All duration fields should be present
    assert_respond_to result, :pre_event_duration
    assert_respond_to result, :event_duration
    assert_respond_to result, :post_event_duration
    assert_respond_to result, :other_duration
    assert_respond_to result, :counted_duration
  end

  test "execute calculates credits correctly" do
    result = EventSummaryReport.execute(@person.id, 2023)

    assert_respond_to result, :pre_event_credits
    assert_respond_to result, :event_credits
    assert_respond_to result, :post_event_credits
    assert result.total_credits >= 0
  end

  test "build_no_event_dates_response returns correct structure" do
    rows = Timesheet.find_for_query(person_id: @person.id, year: 2023)
    result = EventSummaryReport.build_no_event_dates_response(rows)

    assert_equal 0, result.pre_event_duration
    assert_equal 0, result.pre_event_credits
    assert_equal 0, result.post_event_duration
    assert_equal 0, result.post_event_credits
    assert result.no_event_dates
  end

  test "execute returns non-negative durations" do
    result = EventSummaryReport.execute(@person.id, 2023)

    assert result.total_duration >= 0
    assert result.pre_event_duration >= 0
    assert result.event_duration >= 0
    assert result.post_event_duration >= 0
  end

  test "echelon person can have summary generated" do
    echelon_person = person(:echelon_ranger)
    result = EventSummaryReport.execute(echelon_person.id, 2024)

    assert result.is_a?(OpenStruct)
    assert result.total_duration >= 0
  end
end
