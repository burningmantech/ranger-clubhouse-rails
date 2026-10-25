# frozen_string_literal: true

require "ostruct"
require_relative "../event_summary"

# TimesheetWorkSummaryReport
#
# Summarizes a person's timesheet into pre-event, event week, and post-event
# hours and credits.
class EventSummaryReport
  # Generate a work summary for a person's timesheet entries for a given year.
  #
  # @param person_id [Integer] The person's ID
  # @param year [Integer] The year to summarize
  # @param rows [Enumerable<Timesheet>, nil] Already-loaded entries for the person & year
  # @return [OpenStruct] Summary object with duration and credit breakdowns
  def self.execute(person_id, year, rows: nil)
    rows ||= Timesheet.find_for_query(person_id:, year:)
    event_dates = EventDate.find_for_year(year)

    PositionCredit.warm_year_cache(year, rows.map(&:position_id).uniq) if rows.present?

    return build_no_event_dates_response(rows) if event_dates.blank?

    summary = EventSummary.new(
      event_dates.event_start.to_i,
      event_dates.event_end.to_i,
      year
    )

    rows.each do |row|
      summary.compute_totals(
        row.position_id,
        row.on_duty.to_i,
        (row.off_duty || Current.time).to_i,
        row.position.count_hours
      )
      unless row.position.count_hours
        summary.excluded_timesheets << row
      end
    end


    build_response(summary, event_dates)
  end

  # Build response when no event dates are available
  #
  # @param rows [ActiveRecord::Relation] The timesheet entries
  # @return [OpenStruct] Summary with all time attributed to event period
  def self.build_no_event_dates_response(rows)
    time = rows.sum(&:duration)
    credits = rows.sum(&:credits)

    OpenStruct.new(
      pre_event_duration: 0,
      pre_event_credits: 0,
      event_duration: time,
      event_credits: credits,
      post_event_duration: 0,
      post_event_credits: 0,
      other_duration: 0,
      counted_duration: 0,
      total_duration: time,
      total_credits: credits,
      no_event_dates: true
    )
  end

  # Build the response from the computed summary
  #
  # @param summary [EventSummary] The computed work summary
  # @param event_dates [EventDate] The event date record
  # @return [OpenStruct] Summary object with all duration and credit breakdowns
  def self.build_response(summary, event_dates)
    counted_duration = summary.pre_event_duration +
                       summary.event_duration +
                       summary.post_event_duration

    OpenStruct.new(
      pre_event_duration: summary.pre_event_duration,
      pre_event_credits: summary.pre_event_credits,
      event_duration: summary.event_duration,
      event_credits: summary.event_credits,
      post_event_duration: summary.post_event_duration,
      post_event_credits: summary.post_event_credits,
      total_duration: counted_duration + summary.other_duration,
      total_credits: summary.pre_event_credits + summary.event_credits + summary.post_event_credits,
      other_duration: summary.other_duration,
      counted_duration: counted_duration,
      event_start: event_dates.event_start.to_s,
      event_end: event_dates.event_end.to_s,
      excluded_timesheets: summary.excluded_timesheets
    )
  end
end
