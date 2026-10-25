# frozen_string_literal: true

module Timesheets::TimesheetTotalsReportHelper
  # The roster row's second line: what the reader is deciding between before
  # spending a click. Hours first -- the position count only says how the
  # hours are split up.
  def timesheet_totals_report_meta(row)
    "#{hour_minute_format(row.total_duration)} hrs • " \
      "#{pluralize(row.positions.size, "position")}"
  end

  def timesheet_totals_report_badges(row) = person_status_exception_badges(row.person_status)

  def timesheet_totals_report_chips(filter_params, year)
    filter_chips(filter_params, { callsign: "Callsign", status: "Status" }) do |remaining, _key|
      timesheets_timesheet_totals_report_path(year:, **remaining)
    end
  end
end
