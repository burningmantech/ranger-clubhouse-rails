# frozen_string_literal: true

# Rangers who have not confirmed their timesheet is correct (Ember
# reports/timesheet-unconfirmed port). Split into the two groups the /me
# timesheet flow creates: Me::TimesheetController#no_pending_tasks keeps the
# final confirmation button out of reach while any entry is unverified, so
# someone with open entries and someone who simply never clicked are owed two
# different messages.
class Timesheets::TimesheetUnconfirmedController < ApplicationController
  include CsvExportConcern

  layout "timesheets"

  # Upstream TimesheetPolicy@unconfirmedPeople admits Timesheet Management
  # alone; ADMIN is named because Rails RoleManager has no admin-implies-all.
  # The Ember route also lists VIEW_PII, which the API would have answered with
  # a 403 -- a client-side artifact, not a permission.
  authorize_role [Role::ADMIN, Role::TIMESHEET_MANAGEMENT],
                 message: "Admin or Timesheet Management role required " \
                          "to view unconfirmed timesheets."

  # Upstream's own floor. Left at the 1998 default, a year the URL is allowed to
  # ask for is a year the selector cannot show.
  self.year_floor = 2018

  before_action :setup_year

  def index
    rows = UnconfirmedTimesheetsReport.execute(year: @year)
    @to_verify, @to_confirm = rows.partition(&:needs_verifying?)
    @total = rows.size

    respond_to do |format|
      format.html do
        @to_verify_emails = UnconfirmedTimesheetsReport.emails(@to_verify)
        @to_confirm_emails = UnconfirmedTimesheetsReport.emails(@to_confirm)
      end
      format.csv { send_csv(csv_rows, filename: "#{@year}-timesheet-unconfirmed.csv") }
    end
  end

  private

  # Upstream's columns plus the group, so the split the page makes survives into
  # the file rather than having to be re-derived from the count.
  #
  # Grouped, then in callsign order within each group -- upstream's export was
  # one callsign-ordered list, so a callsign that moves between groups between
  # two runs moves in the file too. Sort on Callsign alone to get the old order
  # back.
  def csv_rows
    rows = [["Callsign", "Name", "Email", "Home Phone", "Unverified Entries", "Group"]]

    { "Entries to verify" => @to_verify, "Confirmation not given" => @to_confirm }
      .each do |group, entries|
      entries.each do |entry|
        person = entry.person
        # phone_format, as the page renders it, so screen and file say the same
        # thing -- the column holds three different hand-typed shapes otherwise.
        rows << [person.callsign, entry.name, person.email,
                 helpers.phone_format(person.home_phone),
                 entry.unverified_count, group]
      end
    end

    rows
  end
end
