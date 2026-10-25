# frozen_string_literal: true

# One year of hours and credits, one row per ranger, split into the three parts
# of the season. An audit page first and an export second: most readers take the
# CSV away to check it against tickets and provisions.
class Timesheets::HoursCreditsController < ApplicationController
  include CsvExportConcern

  layout "timesheets"

  # The same pair of readers as the other timesheet-wrangling pages.
  authorize_role [Role::ADMIN, Role::TIMESHEET_MANAGEMENT],
                 message: "Admin or Timesheet Management role required " \
                          "to view the hours and credits report."

  # Left at the 1998 default, a year the URL is allowed to ask for is a year the
  # selector cannot show, and picking it back fires no change event.
  self.year_floor = 2008

  before_action :setup_year

  def index
    @report = HoursCreditsReport.execute(year: @year)
    @filter_params = filter_params
    @rows = filtered_rows(@report.rows, @filter_params)

    respond_to do |format|
      # Only the page needs the select options, and building them means
      # filtering the roster twice more -- a CSV request would pay for that and
      # throw it away.
      format.html { setup_filter_options }
      format.csv do
        send_csv(csv_rows(@rows), filename: "#{@year}-hours-credits.csv")
      end
    end
  end

  private

  # Which choices each select offers comes from the whole roster, so the options
  # do not reshuffle as the other filter changes. The counts beside them come
  # from the roster the other filter leaves.
  def setup_filter_options
    @status_counts = count_by(@report.rows, :status)
    @matching_status_counts = matching_counts(:status)
    @years = @report.rows.map(&:years).uniq.sort
    @matching_years_counts = matching_counts(:years)
  end

  # A select navigates with the page's other filters still applied, so its
  # counts have to promise the roster the choice actually delivers rather than
  # the roster before filtering.
  def matching_counts(key)
    count_by(filtered_rows(@report.rows, @filter_params.except(key)), key)
  end

  # Only the filters actually narrowing the roster, so the chips, the clear-all
  # link, and the export URL all agree about what is applied.
  #
  # A value the roster does not hold is turned back into the "show everything"
  # sentinel and dropped: left alone it would narrow the page to nothing while
  # still drawing a chip claiming it had narrowed it to something. This also
  # disposes of `?status[]=x`, which arrives as an Array and belongs to no
  # roster.
  def filter_params
    UiComponents::FilterBarHelper.active_filters(
      status: known_value(params[:status], @report.rows.map(&:status)),
      years: known_value(params[:years], @report.rows.map { |row| row.years.to_s })
    )
  end

  def known_value(value, allowed)
    UiComponents::FilterBarHelper.known_filter(value, allowed)
  end

  # Filtered in Ruby: the roster is already computed in full to total it, and a
  # second trip to the database could only disagree with the totals on screen.
  #
  # Filters arrive as an argument rather than off the ivar so the caller can ask
  # for a partial set -- each select's counts need the roster narrowed by
  # everything except itself.
  def filtered_rows(rows, filters)
    status = filters[:status]
    years = filters[:years]

    rows.select do |row|
      (status.nil? || row.status == status) &&
        (years.nil? || row.years.to_s == years)
    end
  end

  def count_by(rows, attribute)
    rows.group_by(&attribute).transform_values(&:size)
  end

  # The export carries what the page is showing, filters and all.
  #
  # Name and email are only there for a reader allowed to see them: reading the
  # ledger does not carry permission to see who people are off the playa, and
  # Timesheet Management reads this page without holding either capability.
  def csv_rows(rows)
    names = Current.can_view_pii?
    emails = Current.can_view_email?

    header = ["Callsign"]
    header << "Email" if emails
    header << "Full Name" if names
    header += ["Status", "#{@year} Total Hours", "#{@year} Total Credits",
               "Pre-Event Hours", "Pre-Event Credits",
               "Event Hours", "Event Credits",
               "Post-Event Hours", "Post-Event Credits", "Years"]

    [header, *rows.map { |row| csv_row(row, names, emails) }]
  end

  def csv_row(row, names, emails)
    cells = [row.callsign]
    cells << row.email if emails
    cells << row.name if names

    cells + [row.status,
             helpers.hour_format(row.counted_duration),
             credits(row.total_credits),
             helpers.hour_format(row.pre_event_duration), credits(row.pre_event_credits),
             helpers.hour_format(row.event_duration), credits(row.event_credits),
             helpers.hour_format(row.post_event_duration), credits(row.post_event_credits),
             row.years]
  end

  # Two decimals even at zero, so a column of credits reads as one column of
  # numbers in a spreadsheet.
  def credits(value) = "%.2f" % value.to_f
end
