# frozen_string_literal: true

# Every timesheet of an event year, grouped by callsign (Ember
# reports/timesheet-by-callsign port). The roster drills down into one person's
# entries, as the no-shows and asset-records indexes beside it do -- upstream's
# accordion stacked 840 people and 5,600 entries onto one page.
class Timesheets::TimesheetsByCallsignController < ApplicationController
  include CsvExportConcern
  include CallsignStatusFilterConcern
  include PersonLookupConcern

  layout "timesheets"

  # Upstream TimesheetPolicy: the before hook admits Admin and Timesheet
  # Management, and timesheetByCallsign() admits Event Management. The same
  # triple the two sibling /timesheets pages spell. Full Report Access is
  # deliberately NOT here -- it widens which positions a reader sees (see
  # TimesheetByCallsignReport), it is not a key to the page.
  authorize_role [Role::ADMIN, Role::TIMESHEET_MANAGEMENT, Role::EVENT_MANAGEMENT],
                 message: "Admin, Timesheet Management, or Event Management role required " \
                          "to view timesheets by callsign."

  # Upstream's own floor. Left at the 1998 default, a year the URL is allowed to
  # ask for is a year the selector cannot show, and picking it back fires no
  # change event.
  self.year_floor = 2008

  before_action :setup_year
  before_action :set_person, only: :person

  def index
    # The roster and the export read the same year twice over, so each format
    # builds only what it needs -- a CSV request that first built the whole
    # roster and threw it away paid for the year twice.
    respond_to do |format|
      format.html do
        @report = TimesheetByCallsignReport.summary(year: @year, viewer: Current.person)
        @filter_params = filter_params
        # Ordering comes from the whole roster so the options do not reshuffle
        # as the callsign filter changes; the labels count only the people a
        # choice would actually deliver, since the select navigates with the
        # callsign filter still applied.
        @status_counts = count_by_status(@report.people)
        @matching_status_counts =
          count_by_status(filtered_people(@report.people, @filter_params.except(:status)))
        @people = filtered_people(@report.people, @filter_params)
      end

      format.csv do
        rows = TimesheetByCallsignReport.entries(year: @year, viewer: Current.person)
        credits = TimesheetByCallsignReport.credits_by_id(rows)
        send_csv(csv_rows(rows.sort_by { |row| [row.person&.callsign.to_s.downcase, row.on_duty] },
                          credits),
                 filename: "#{@year}-timesheets-by-callsign.csv")
      end
    end
  end

  def person
    @detail = TimesheetByCallsignReport.person(year: @year, person_id: @person.id,
                                               viewer: Current.person)
    return if hidden_person_redirect

    respond_to do |format|
      format.html
      format.csv do
        send_csv(csv_rows(@detail.entries, @detail.credits),
                 filename: "#{@year}-#{@person.callsign.parameterize}-timesheet.csv")
      end
    end
  end

  private

  # Also PersonLookupConcern#set_person's own "no such person" redirect
  # target, so the two share one wording -- a reader scoped to their own
  # teams' positions gets the same answer for a person they may not see as
  # for one who does not exist, and the URL cannot be told apart from the
  # outside.
  def person_not_found_path = timesheets_timesheets_by_callsign_path(year: @year)

  # A reader scoped to their own teams' positions gets the same answer for a
  # person they may not see as for one who does not exist. Rendering the page
  # would put the callsign in the heading, which is a person page by another
  # name -- and Timesheet Management, who reads this report, is deliberately
  # kept off /person/:id.
  #
  # Only for a scoped reader: a full-report reader seeing an empty year is
  # reading a true and useful page.
  def hidden_person_redirect
    return false if @detail.status == TimesheetByCallsignReport::FULL_REPORT
    return false if @detail.entries.any?

    redirect_to person_not_found_path, error: PERSON_NOT_FOUND
    true
  end

  # Upstream's eleven columns, in its order.
  #
  # getlocal before iso8601, as the sibling reports do: a datetime read comes
  # back cast into Time.zone, an hour ahead of the stored wall clock for the
  # half of the year the machine is not on the same offset. Without it a
  # January shift exports an hour later than the page shows it.
  def csv_rows(entries, credits)
    rows = [["Callsign", "Status", "From", "To", "Hours", "Credits", "Position",
             "Count Hours", "Shift Begins", "Shift Duration", "Shift Description"]]

    entries.each do |entry|
      slot = entry.slot
      rows << [helpers.person_display_name(entry.person, entry.person_id, blank: nil),
               entry.person&.status,
               entry.on_duty.getlocal.iso8601,
               entry.off_duty&.getlocal&.iso8601,
               helpers.hour_format(entry.duration),
               "%.2f" % credits.fetch(entry.id, 0.0),
               entry.position&.title,
               entry.position&.count_hours ? "Y" : "N",
               slot&.begins&.getlocal&.iso8601,
               slot ? helpers.hour_format(slot.duration) : nil,
               slot&.description]
    end

    rows
  end
end
