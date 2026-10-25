# frozen_string_literal: true

# Every timesheet of an event year, grouped by position (Ember
# reports/timesheet-by-position port). The index drills down into one position,
# as its Timesheets by Callsign twin drills down into one person -- upstream's
# accordion stacked 140 positions and 5,400 entries onto one page.
class Timesheets::TimesheetByPositionController < ApplicationController
  include CsvExportConcern
  include PositionLookupConcern

  layout "timesheets"

  # Upstream TimesheetPolicy: the before hook admits Admin and Timesheet
  # Management, and timesheetByPosition() admits Event Management. The same
  # triple the sibling /timesheets pages spell. Full Report Access is
  # deliberately NOT here -- it widens which positions a reader sees (see
  # TimesheetYearReport), it is not a key to the page.
  authorize_role [Role::ADMIN, Role::TIMESHEET_MANAGEMENT, Role::EVENT_MANAGEMENT],
                 message: "Admin, Timesheet Management, or Event Management role required " \
                          "to view timesheets by position."

  # Upstream's own floor. Left at the 1998 default, a year the URL is allowed to
  # ask for is a year the selector cannot show, and picking it back fires no
  # change event.
  self.year_floor = 2008

  before_action :setup_year
  before_action :set_position, only: :position

  def index
    # The index and the export read the same year twice over, so each format
    # builds only what it needs -- a CSV request that first built the whole
    # index and threw it away paid for the year twice.
    respond_to do |format|
      format.html do
        @report = TimesheetByPositionReport.summary(year: @year, viewer: Current.person)
        @filter_params = filter_params
        # Ordering comes from the whole index so the options do not reshuffle as
        # the title filter changes; the labels count only the positions a choice
        # would actually deliver, since the select navigates with the title
        # filter still applied.
        @active_counts = count_by_active(@report.positions)
        @matching_active_counts =
          count_by_active(filtered_positions(@report.positions, @filter_params.except(:active)))
        @positions = filtered_positions(@report.positions, @filter_params)
      end

      format.csv do
        rows = TimesheetByPositionReport.entries(year: @year, viewer: Current.person)
        send_csv(csv_rows(rows, TimesheetByPositionReport.credits_by_id(rows),
                          include_position: true),
                 filename: "#{@year}-timesheets-by-position.csv")
      end
    end
  end

  def position
    @detail = TimesheetByPositionReport.position(year: @year, position_id: @position.id,
                                                 viewer: Current.person)
    return if hidden_position_redirect

    respond_to do |format|
      format.html
      format.csv do
        send_csv(csv_rows(@detail.entries, @detail.credits),
                 filename: "#{@year}-#{export_slug(@position)}.csv")
      end
    end
  end

  private

  # parameterize keeps only ASCII alphanumerics, so a title written in another
  # script -- or in punctuation alone -- comes back empty and every such
  # position would download as "<year>-.csv", each overwriting the last. The id
  # is the fallback because it is the one thing every position has.
  def export_slug(position)
    position.title.parameterize.presence || "position-#{position.id}"
  end

  def position_not_found_path
    timesheets_timesheet_by_position_path(year: @year)
  end

  # A reader scoped to their own teams' positions is turned back from any other
  # position, and gets the same answer as for a position that does not exist.
  #
  # The report answers this off the scope it already looked up, rather than the
  # page inferring it from an empty result as the by-callsign twin has to do for
  # people: a position the reader owns but which no one rangered this year is a
  # page they are entitled to, and reading "could not be found" there would be a
  # lie about their own team.
  def hidden_position_redirect
    return false if @detail.readable

    redirect_to position_not_found_path, error: POSITION_NOT_FOUND
    true
  end

  # Only the filters actually narrowing the index, so the chips and the
  # clear-all link agree about what is applied. The export is deliberately not
  # among them -- it is offered as "Export All to CSV" and carries only the
  # year, so a filtered page still exports the whole year.
  #
  # The title is demanded as a String: `?title[]=x` hands back an Array and
  # `?title[a]=b` an ActionController::Parameters, neither of which is blank nor
  # the "all" sentinel, so both would survive as an active filter that matches
  # nothing and draws a chip reading `Position: ["x"]`.
  def filter_params
    UiComponents::FilterBarHelper.active_filters(
      title: string_param(:title),
      active: string_param(:active)
    )
  end

  def string_param(key)
    value = params[key]
    value.is_a?(String) ? value.strip.presence : nil
  end

  # Keyed by the words the labels need to read: a status is shown exactly as it
  # is spelled here, by the select and by the chip alike.
  def count_by_active(positions)
    positions.group_by { |row| active_key(row) }.transform_values(&:size)
  end

  # Filtered in Ruby: the index is already loaded in full to total it, and a
  # second trip to the database could only disagree with the totals on screen.
  def filtered_positions(positions, filters)
    title = filters[:title]&.downcase
    active = filters[:active]

    positions.select do |row|
      (title.nil? || row.title.downcase.include?(title)) &&
        (active.nil? || active == active_key(row))
    end
  end

  # Compared as the same word the select offers rather than as a boolean, so a
  # value that is neither "active" nor "inactive" matches nothing. Reading it as
  # `row.active == (active == "active")` turns every unrecognized value into a
  # request for the inactive positions.
  def active_key(row)
    row.active ? "active" : "inactive"
  end

  # Upstream's nine columns, in its order, with the Position column prepended
  # for the whole-report export.
  #
  # getlocal before iso8601, as the sibling reports do: a datetime read comes
  # back cast into Time.zone, an hour ahead of the stored wall clock for the
  # half of the year the machine is not on the same offset. Without it a
  # January shift exports an hour later than the page shows it.
  def csv_rows(entries, credits, include_position: false)
    header = ["From", "To", "Hours", "Credits", "Callsign", "Status",
              "Shift Begins", "Shift Duration", "Shift Description"]
    header.unshift("Position") if include_position
    header << "Email" if Current.can_view_email?

    rows = [header]

    entries.each do |entry|
      slot = entry.slot
      row = [entry.on_duty.getlocal.iso8601,
             entry.off_duty&.getlocal&.iso8601,
             helpers.hour_format(entry.duration),
             "%.2f" % credits.fetch(entry.id, 0.0),
             helpers.person_display_name(entry.person, entry.person_id, blank: nil),
             # Upstream declares this column and never fills it -- its export
             # builder has no status key at all. Filled here: a blank column in
             # every row of every export is a column that was meant to say
             # something.
             entry.person&.status || "deleted",
             slot&.begins&.getlocal&.iso8601,
             slot ? helpers.hour_format(slot.duration) : nil,
             slot&.description]
      row.unshift(entry.position&.title) if include_position
      row << entry.person&.email if Current.can_view_email?

      rows << row
    end

    rows
  end
end
