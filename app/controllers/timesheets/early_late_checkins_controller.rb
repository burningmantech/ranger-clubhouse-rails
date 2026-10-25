# frozen_string_literal: true

# Check-ins that landed outside the window around their scheduled shift start
# (Ember reports/early-late-checkins port). Early and late are shown apart, each
# ordered by how far outside the window it landed, because the two are different
# problems: early arrivals crowd a shift that has not started, late ones leave a
# shift short.
class Timesheets::EarlyLateCheckinsController < ApplicationController
  include CsvExportConcern

  layout "timesheets"

  # Upstream TimesheetPolicy: the before hook admits Admin and Timesheet
  # Management, and earlyLateCheckins() adds no one. Deliberately narrower than
  # the sibling /timesheets pages -- Event Management reads those, not this one.
  authorize_role [Role::ADMIN, Role::TIMESHEET_MANAGEMENT],
                 message: "Admin or Timesheet Management role required " \
                          "to view early and late check-ins."

  # Upstream's own floor. Left at the 1998 default, a year the URL is allowed to
  # ask for is a year the selector cannot show, and picking it back fires no
  # change event.
  self.year_floor = 2010

  before_action :setup_year

  def index
    @report = EarlyLateCheckInReport.execute(year: @year)
    # Whole-year, like @report.positions: it drives the via select, which has to
    # keep offering the methods the reader is not looking at.
    @via_counts = @report.entries.map { |entry| EarlyLateCheckInReport.via_param(entry.via) }.tally
    @filters = filter_params
    entries = filtered_entries

    respond_to do |format|
      format.html do
        # Worst first within each half: the check-in that missed by three hours
        # is the one worth reading about, and it is nowhere near the top in
        # check-in order. Ties break on the callsign -- sort_by is not stable,
        # and a table that reshuffles between two reads cannot be compared.
        @early, @late = entries.partition(&:early?).map { |rows|
          rows.sort_by { |entry| [-entry.distance, entry.callsign.downcase] }
        }

        # The rollups follow the filter, so the page totals what it is showing.
        # @report.positions stays whole-year: it drives the filter's own select,
        # which has to keep offering the positions the reader is not looking at.
        @people = EarlyLateCheckInReport.person_totals(entries)
        @positions = EarlyLateCheckInReport.position_totals(entries)

        # Counted here rather than off @late, because a missing-entry request is
        # not one side of the report: it is how the row got written at all, and
        # it lands on both halves. A shift the ranger never signed into gets its
        # times typed in afterwards, so an early or late flag on one of these
        # rows is an argument about a remembered hour, not a check-in anyone
        # made at the wrong time.
        @missing_entries = entries.count { |entry| entry.via == TimesheetLog::VIA_MISSING_ENTRY }
      end

      format.csv do
        send_csv(csv_rows(entries), filename: "#{@year}-early-late-checkins.csv")
      end
    end
  end

  private

  # Only the filters actually narrowing something: an unset one draws no chip
  # and is dropped from the export link and the chips' own remove URLs.
  def filter_params
    UiComponents::FilterBarHelper.active_filters(
      position_id: position_filter,
      callsign: callsign_filter,
      via: via_filter
    )
  end

  # The filter narrows both halves and the export alike, so what is on screen is
  # what downloads. Neither select offers a value the report cannot answer -- a
  # position that flagged no one, a method nothing was entered by -- so "all" is
  # the only way to ask for an empty table.
  def filtered_entries
    position_id = @filters[:position_id]
    callsign = @filters[:callsign]&.downcase
    via = @filters[:via]

    @report.entries.select do |entry|
      (position_id.nil? || entry.position_id == position_id) &&
        (callsign.nil? || entry.callsign.downcase.include?(callsign)) &&
        (via.nil? || EarlyLateCheckInReport.via_param(entry.via) == via)
    end
  end

  # Demanded as a plain integer: `?position_id[]=1` hands back an Array, which
  # matches no entry and would draw a chip reading `Position: ["1"]`.
  def position_filter
    value = params[:position_id]
    return nil unless value.is_a?(String) && value.match?(/\A\d+\z/)

    id = value.to_i
    id if @report.positions.any? { |position| position.position_id == id }
  end

  # Substring, on the callsign the row prints -- which is "Deleted #12" for a
  # ranger who is gone, so the rows a reader cannot click through to are still
  # reachable by the only name they have.
  #
  # Demanded as a String for the same reason as the others: `?callsign[]=x`
  # hands back an Array, which has no #downcase and would raise rather than
  # match nothing.
  def callsign_filter
    value = params[:callsign]
    value.strip.presence if value.is_a?(String)
  end

  def via_filter
    value = params[:via]
    value if value.is_a?(String) && @via_counts.key?(value)
  end

  # Upstream's columns, in its order, and in check-in order rather than the
  # page's -- the export is the audit trail of the year, read top to bottom.
  #
  # The two timestamps are written as the wall clock the column stores, which is
  # what the page shows: datetime_format re-stamps the digits with a display
  # zone rather than converting them (see parse_time_in_zone), so anything that
  # converts here -- getlocal to the host's zone, iso8601 to Time.zone's offset
  # -- exports a different hour than the row the reader is looking at, and on a
  # UTC server a different hour than the shift actually began. These columns
  # carry no offset because the column they come from records none.
  def csv_timestamp(time) = time.strftime("%FT%T")

  def csv_rows(entries)
    rows = [["Callsign", "Position", "On Duty", "Via", "Type", "By (minutes)",
             "Shift Start", "Shift Description"]]

    entries.each do |entry|
      rows << [entry.callsign,
               entry.position_title,
               csv_timestamp(entry.on_duty),
               helpers.check_in_via_label(entry.via),
               entry.type,
               entry.distance,
               csv_timestamp(entry.slot_begins),
               entry.slot_description]
    end

    rows
  end
end
