# frozen_string_literal: true

# How full every active shift of an event year is, grouped by position. The
# index drills down into one position's shifts, the way the schedule report
# beside it does.
class Scheduling::ShiftSignupsController < ApplicationController
  include CsvExportConcern
  include PositionLookupConcern

  layout "scheduling"

  # The same three roles the schedule reports beside it admit: Admin and Edit
  # Slots reach every slot report, and Event Management reads the reports.
  authorize_role [Role::ADMIN, Role::EDIT_SLOTS, Role::EVENT_MANAGEMENT],
                 message: "Admin, Edit Slots, or Event Management role required " \
                          "to view the shift sign-ups report."

  # The first year worth offering. Left at the 1998 default, the selector would
  # list decades of years that hold no shifts.
  self.year_floor = 2008

  # The two ways of narrowing the list, as they are spelled in the URL. What
  # each one is called on screen is the helper's to say.
  SHOW_EMPTY = "empty"
  SHOW_LOW = "low"
  SHOW_FILTERS = [SHOW_EMPTY, SHOW_LOW].freeze

  before_action :setup_year
  before_action :set_position, only: :position

  # Each format builds only what it needs, so an export does not first total
  # every position and throw it away.
  def index
    respond_to do |format|
      format.html do
        @rows = ShiftSignupsReport.index(year: @year)
        # Only the filter actually narrowing the list, so the chip, the
        # clear-all link, and the year selector all agree about what is on.
        @filter_params = UiComponents::FilterBarHelper.active_filters(show: show_param)
        @shown_rows = filtered_rows(@rows)
      end

      # The whole year, never the filtered view: an export named for the year
      # that quietly held back most of it is one no one can trust.
      format.csv do
        send_csv(csv_rows(ShiftSignupsReport.shifts(year: @year)),
                 filename: "#{@year}-shift-signups.csv")
      end
    end
  end

  def position
    @detail = ShiftSignupsReport.position(year: @year, position_id: @position.id)

    respond_to do |format|
      format.html
      format.csv do
        send_csv(csv_rows(@detail.shifts),
                 filename: "#{@year}-shift-signups-#{@position.title.parameterize}.csv")
      end
    end
  end

  private

  def position_not_found_path
    scheduling_shift_signups_path(year: @year)
  end

  # Anything the page does not offer shows everything. A stale bookmark or a
  # typo would otherwise narrow nothing while still drawing a chip claiming it
  # did, and `?show[]=x` arrives as an Array that no lookup matches.
  def show_param
    UiComponents::FilterBarHelper.known_filter(params[:show], SHOW_FILTERS)
  end

  # Filtered in Ruby: the list is already loaded in full to total it, and a
  # second trip to the database could only disagree with the totals on screen.
  # What counts as thinly covered is the report's to say, not this page's.
  def filtered_rows(rows)
    case @filter_params[:show]
    when SHOW_EMPTY then rows.select { |row| row.empty_count.positive? }
    when SHOW_LOW then rows.select(&:low?)
    else rows
    end
  end

  # One row per shift, in the order the page lists them. Times go out as they
  # are read, which is the clock the page prints; shifting them into the
  # machine's own zone first would export every shift an hour off from the page.
  def csv_rows(shifts)
    rows = [["Position", "Begins", "Ends", "Description", "Signed Up", "Max"]]

    shifts.each do |shift|
      slot = shift.slot
      rows << [slot.position_title, slot.begins.iso8601, slot.ends.iso8601,
               slot.description, shift.sign_up_count, slot.max]
    end

    rows
  end
end
