# frozen_string_literal: true

# Who signed up for a shift and was never on duty for it. The positions index
# drills down into one position's shifts, as the flake and shift drop reports
# beside it do.
class Scheduling::NoShowsReportController < ApplicationController
  include CsvExportConcern
  include PositionLookupConcern

  layout "scheduling"

  # Upstream TimesheetPolicy: the before hook admits Admin and Timesheet
  # Management, and noShowsReport() admits Event Management. Deliberately NOT
  # the flake report's role set -- Edit Slots reads that page and has no claim
  # on this one. (The Ember route gates on MANAGE, which the API never honored;
  # the policy is the authority.)
  authorize_role [Role::ADMIN, Role::TIMESHEET_MANAGEMENT, Role::EVENT_MANAGEMENT],
                 message: "Admin, Timesheet Management, or Event Management role required " \
                          "to view the no shows report."

  # The year selector's own floor, matching upstream's list. Left at the 1998
  # default, a year the URL is allowed to ask for is a year the selector cannot
  # show, and picking it back fires no change event.
  self.year_floor = 2019

  before_action :setup_year
  before_action :set_position, only: :position

  def index
    @summary = NoShowReport.summary(year: @year)
  end

  # The export is this position's year, so it is built from the page's own
  # detail rather than from a second scan.
  def position
    @detail = NoShowReport.position(year: @year, position: @position)

    respond_to do |format|
      format.html
      format.csv do
        send_csv(csv_rows, filename: "#{@year}-no-shows-#{@position.title.parameterize}.csv")
      end
    end
  end

  private

  def position_not_found_path
    scheduling_no_shows_report_path(year: @year)
  end

  # Upstream's four columns, with its "Description" renamed to match the page.
  #
  # getlocal before iso8601, as the sibling reports do: a datetime read comes
  # back cast into Time.zone, an hour ahead of the stored wall clock for the
  # half of the year the machine is not on the same offset. Without it a
  # January shift exports an hour later than the page shows it.
  def csv_rows
    rows = [["Position", "Shift Start", "Shift", "Callsign"]]

    @detail.slot_details.each do |detail|
      detail.no_shows.each do |no_show|
        rows << [@position.title, detail.slot.begins.getlocal.iso8601,
                 detail.slot.description, no_show.callsign]
      end
    end

    rows
  end
end
