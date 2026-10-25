# frozen_string_literal: true

# Total service years for every Active Ranger. (Ember reports/freaking-years
# port.) The index lists the service-year groups; #show is one group's roster.
# Upstream drew every group as an accordion on one page.
#
# Deliberately NOT year-scoped: service is all-time and there is no year
# selector. Current.year only names the export files, as it does upstream.
class Quartermaster::FreakingYearsController < ApplicationController
  include CsvExportConcern

  layout "quartermaster"

  # Upstream's AwardPolicy#serviceYearsReport: Quartermaster, with Admin through
  # the policy's #before. Timesheet Management is NOT carried over the way
  # Events Rangered carries it -- that grant was TimesheetPolicy's, and this
  # report never lived there.
  authorize_role [Role::ADMIN, Role::QUARTERMASTER],
                 message: "Admin or Quartermaster role required to view service years."

  # Upstream's columns, for both exports.
  CSV_HEADER = ["Callsign", "Last Name", "First Name", "Total Years of Service",
                "First Year", "Last Year"].freeze

  def index
    @rows = FreakingYearsReport.execute
    # The rows arrive longest service first, so the groups do too.
    @groups = @rows.group_by(&:years)

    respond_to do |format|
      format.html
      format.csv { send_csv(csv_rows(@rows), filename: "#{Current.year}-freaking-years.csv") }
    end
  end

  def show
    @years = params[:years].to_i
    # In memory: the whole roster is one small pluck, and counting a JSON
    # array's length in the database would take raw SQL.
    @rows = FreakingYearsReport.execute.select { |row| row.years == @years }

    # A group no one holds has no page. This is reachable from any bookmark:
    # a group empties out the moment its last person earns another year.
    if @rows.empty?
      return redirect_to quartermaster_freaking_years_path,
                         error: "No Active Ranger has #{helpers.pluralize(@years, "service year")}."
    end

    respond_to do |format|
      format.html
      format.csv { send_csv(csv_rows(@rows), filename: "#{Current.year}-freaking-years-#{@years}.csv") }
    end
  end

  private

  # The last-name sort is upstream's. Someone with no service years has blank
  # First and Last Year cells where upstream wrote "n/a", so both columns stay
  # numeric in a spreadsheet.
  def csv_rows(rows)
    sorted = rows.sort_by { |row| [row.last_name.downcase, row.first_name.downcase] }

    sorted.each_with_object([CSV_HEADER]) do |row, csv|
      csv << [row.callsign, row.last_name, row.first_name, row.years, row.first_year, row.last_year]
    end
  end
end
