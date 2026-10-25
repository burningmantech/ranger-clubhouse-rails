# frozen_string_literal: true

# Who put in the most hours in one year of a span. One page: the span and the
# number of people to list all ride in the query string, so a report can be
# bookmarked and passed on.
class Timesheets::TopHourEarnersController < ApplicationController
  include CsvExportConcern

  layout "timesheets"

  # The same pair of readers as the other timesheet-wrangling pages.
  authorize_role [Role::ADMIN, Role::TIMESHEET_MANAGEMENT],
                 message: "Admin or Timesheet Management role required " \
                          "to view the top hour earners report."

  # No year filter of its own: the span replaces it, and both ends are read
  # straight from the query string.
  def index
    @report = TopHourEarnersReport.execute(start_year: params[:start_year],
                                           end_year: params[:end_year],
                                           limit: params[:limit])

    respond_to do |format|
      format.html
      format.csv do
        send_csv(csv_rows(@report),
                 filename: "top-hour-earners-#{@report.start_year}-#{@report.end_year}.csv")
      end
    end
  end

  private

  # Callsign and status, then the ranking figures and the same year columns the
  # page draws.
  #
  # Name and email are only there for a reader allowed to see them. Reading this
  # report does not carry that permission: a ranger with no preferred name is
  # named by their legal name, which is held to the same bar as their phone
  # number and address, and an address is held to a bar of its own. A reader
  # without either still gets a usable export, because a callsign is how this
  # organisation names people.
  def csv_rows(report)
    names = Current.can_view_pii?
    emails = Current.can_view_email?

    header = ["Callsign"]
    header << "Name" if names
    header << "Status"
    header << "Email" if emails

    [header + ["Top Hours", "Top Year", *report.years],
     *report.rows.map { |row| csv_row(row, report.years, names, emails) }]
  end

  def csv_row(row, years, names, emails)
    cells = [row.callsign]
    cells << row.name if names
    cells << row.status
    cells << row.email if emails

    cells + [helpers.hour_format(row.top_duration), row.top_year,
             *years.map { |year| helpers.hour_format(row.duration_for(year)) }]
  end
end
