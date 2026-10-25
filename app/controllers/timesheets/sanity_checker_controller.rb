# frozen_string_literal: true

# Timesheet entries of one event year that look wrong (Ember
# reports/timesheet-sanity-checker port). Upstream stacked eight collapsed
# accordions, each holding a full table, on one page; the index here is a
# triage board and each check drills into its own page.
class Timesheets::SanityCheckerController < ApplicationController
  include CsvExportConcern

  layout "timesheets"

  # Upstream TimesheetPolicy#sanityChecker: Admin and Timesheet Management
  # alone. Deliberately narrower than the /timesheets pages next door -- an
  # Event Management reader shown the menu link would only be bounced off the
  # page, as with Early / Late Check-Ins and Correction Requests.
  authorize_role [Role::ADMIN, Role::TIMESHEET_MANAGEMENT],
                 message: "Admin or Timesheet Management role required to view the " \
                          "timesheet sanity checker."

  # Upstream's client-side floor. Left at the 1998 default, a year the URL is
  # allowed to ask for is a year the selector cannot show, and picking it back
  # fires no change event.
  self.year_floor = 2010

  UNKNOWN_CHECK = "That sanity check does not exist."

  # As many findings as a page can usefully carry. Only "No credits" can reach
  # it: a year whose position_credit table was never filled in prices every
  # entry at zero, so the check answers with the whole year. The export is not
  # capped -- a spreadsheet is how you handle two thousand rows.
  PAGE_LIMIT = 500

  before_action :setup_year
  before_action :set_check, only: :check

  def index
    @summary = TimesheetSanityCheckReport.summary(year: @year)
  end

  def check
    respond_to do |format|
      format.html do
        # One over the cap, so the overflow is visible without a second pass
        # over the year to count it.
        @findings = TimesheetSanityCheckReport.findings(year: @year, check: @check,
                                                        limit: PAGE_LIMIT + 1)
        @truncated = @findings.size > PAGE_LIMIT
        @findings = @findings.first(PAGE_LIMIT) if @truncated
      end

      format.csv do
        @findings = TimesheetSanityCheckReport.findings(year: @year, check: @check)
        send_csv(csv_rows, filename: "#{@year}-#{@check.to_s.dasherize}.csv")
      end
    end
  end

  private

  # Validated against the report's own key list, which is the set findings will
  # dispatch on. An unrecognized key is a stale bookmark rather than an
  # exception, so it lands back on the index with a reason.
  def set_check
    @check = params[:check].to_s.underscore
                           .presence_in(TimesheetSanityCheckReport::KEYS.map(&:to_s))&.to_sym
    return if @check

    redirect_to timesheets_sanity_checker_path(year: @year), error: UNKNOWN_CHECK
  end

  # The two person-grain checks flatten to their entries for the export: a CSV
  # row per finding would have to fold several entries into one cell, and
  # nothing downstream could read it back apart.
  def export_entries
    return @findings unless person_grain?

    @findings.flat_map { |finding| Array(finding.entries) }
  end

  def person_grain? = TimesheetSanityCheckReport.grain(@check) == :people

  # getlocal before iso8601, as the sibling timesheet exports do: a datetime
  # read comes back cast into Time.zone, an hour ahead of the stored wall clock
  # for the half of the year the machine is not on the same offset.
  def csv_rows
    header = ["Callsign", "Position", "On Duty", "Off Duty", "Hours",
              "Shift Begins", "Shift Duration", "Shift Description"]
    header << "Email" if Current.can_view_email?

    rows = [header]

    export_entries.each do |entry|
      slot = entry.slot
      row = [helpers.person_display_name(entry.person, entry.person_id, blank: nil),
             entry.position&.title || "Position ##{entry.position_id}",
             entry.on_duty.getlocal.iso8601,
             entry.off_duty&.getlocal&.iso8601,
             helpers.hour_format(entry.duration),
             slot&.begins&.getlocal&.iso8601,
             slot ? helpers.hour_format(slot.duration) : nil,
             slot&.description]
      row << entry.person&.email if Current.can_view_email?

      rows << row
    end

    rows
  end
end
