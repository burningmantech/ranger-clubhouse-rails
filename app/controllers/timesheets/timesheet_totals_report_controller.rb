# frozen_string_literal: true

# One year of hours and credits per person, counting only positions that
# count hours. Roster index drilling down into one person; only the index
# answers CSV -- there is no per-person export, matching upstream.
class Timesheets::TimesheetTotalsReportController < ApplicationController
  include CsvExportConcern
  include CallsignStatusFilterConcern
  include PersonLookupConcern

  layout "timesheets"

  # This report is only ever the whole report: it has no team-scoping story,
  # so it is gated to the two roles that could see everything on the sibling
  # reports anyway.
  authorize_role [Role::ADMIN, Role::TIMESHEET_MANAGEMENT],
                 message: "Admin or Timesheet Management role required to view timesheet totals."

  self.year_floor = 2008

  before_action :setup_year
  before_action :set_person, only: :person

  def index
    @people = TimesheetTotalsReport.summary(year: @year)

    respond_to do |format|
      format.html do
        @filter_params = filter_params
        @status_counts = count_by_status(@people)
        @matching_status_counts =
          count_by_status(filtered_people(@people, @filter_params.except(:status)))
        @filtered_people = filtered_people(@people, @filter_params)
      end

      format.csv do
        send_csv(csv_rows(@people), filename: "#{@year}-timesheet-totals.csv")
      end
    end
  end

  def person
    @detail = TimesheetTotalsReport.person(year: @year, person_id: @person.id)
  end

  private

  def person_not_found_path = timesheets_timesheet_totals_report_path(year: @year)

  # One row per person-position pair, matching the roster's own grouping --
  # the total column on screen is the sum of exactly these rows.
  def csv_rows(people)
    [["Callsign", "Status", "Position", "#{@year} Hours", "#{@year} Credits"]] +
      people.flat_map do |person_row|
        person_row.positions.map do |position_row|
          [person_row.callsign, person_row.person_status, position_row.title,
           helpers.hour_format(position_row.duration), "%.2f" % position_row.credits]
        end
      end
  end
end
