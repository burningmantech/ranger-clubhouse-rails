# frozen_string_literal: true

# Corrections and missing-entry requests still waiting on a decision (Ember
# reports/timesheet-correction-requests port).
class Timesheets::CorrectionRequestsController < ApplicationController
  include CsvExportConcern

  layout "timesheets"

  # Upstream TimesheetPolicy: the before hook admits Admin and Timesheet
  # Management, and correctionRequests() adds no one. Narrower than most of the
  # sibling /timesheets pages -- the same gate as Early / Late Check-Ins, and
  # for the same reason: Event Management reads the others, not this one.
  authorize_role [Role::ADMIN, Role::TIMESHEET_MANAGEMENT],
                 message: "Admin or Timesheet Management role required " \
                          "to view timesheet correction requests."

  # Upstream's own floor. Left at the 1998 default, a year the URL is allowed to
  # ask for is a year the selector cannot show.
  self.year_floor = 2018

  before_action :setup_year

  def index
    @report = CorrectionRequestsReport.execute(year: @year)
    @letter = letter_filter
    @entries = filtered_entries

    respond_to do |format|
      format.html
      format.csv do
        send_csv(csv_rows(@entries), filename: "#{@year}-correction-requests.csv")
      end
    end
  end

  private

  # The rollups above the table are built from this, so the page totals what it
  # is showing rather than the year behind it.
  def filtered_entries
    return @report.entries unless @letter

    @report.entries.select { |entry| entry.letter == @letter }
  end

  # Only a letter the report actually holds. Anything else is a filter that can
  # only return nothing, and it would draw a chip naming a letter no one has.
  # `?letter[]=A` hands back an Array, which is neither a String nor one
  # character long.
  def letter_filter
    value = params[:letter]
    return nil unless value.is_a?(String) && value.length == 1

    letter = value.upcase
    letter if @report.letters.include?(letter)
  end

  # The two timestamps are written as the wall clock the column stores, which is
  # what the page shows: anything that converts here -- getlocal to the host's
  # zone, iso8601 to Time.zone's offset -- exports a different hour than the row
  # the reader is looking at.
  def csv_timestamp(time) = time.strftime("%FT%T")

  # The reason travels with the row: it is the whole point of the page, and a
  # file that dropped it would send the reader back to the browser to decide
  # anything. Each note names its author, as the opened row does.
  def csv_reason(entry)
    entry.notes.map { |note| "#{helpers.correction_request_note_author(note)}: #{note.note}" }
         .join("\n")
  end

  def csv_rows(entries)
    rows = [["Callsign", "Type", "Position", "On Duty", "Off Duty", "Hours",
             "Credits", "Reason"]]

    entries.each do |entry|
      rows << [entry.callsign,
               entry.missing? ? "Missing Entry" : "Correction",
               entry.position_title,
               csv_timestamp(entry.on_duty),
               csv_timestamp(entry.off_duty),
               # Hours as a sortable decimal rather than the page's "1 day 11
               # hours", as the sibling exports are; credits at the precision
               # the page shows, so the two do not disagree over a raw float's
               # trailing digits.
               helpers.hour_format(entry.duration),
               helpers.credit_format_short(entry.credits),
               csv_reason(entry)]
    end

    rows
  end
end
