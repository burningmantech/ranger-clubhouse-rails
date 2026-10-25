# frozen_string_literal: true

# Every shift of an event year with its sign-ups, grouped by position (Ember
# reports/schedule-by-position port). The index drills down into one position,
# the way its callsign sibling drills into one person -- upstream stacked all
# hundred-and-some positions onto one page as accordions.
class Scheduling::ScheduleByPositionController < ApplicationController
  include CsvExportConcern
  include PositionLookupConcern

  layout "scheduling"

  # Upstream SlotPolicy: the before hook admits Admin and Edit Slots, and
  # report() admits Event Management. The same triple the callsign sibling
  # spells, off the same policy.
  authorize_role [Role::ADMIN, Role::EDIT_SLOTS, Role::EVENT_MANAGEMENT],
                 message: "Admin, Edit Slots, or Event Management role required " \
                          "to view the schedule by position."

  # Upstream's own YearSelect floor.
  self.year_floor = 2008

  before_action :setup_year
  before_action :set_position, only: :position

  def index
    @rows = ScheduleByPositionReport.index(year: @year)
  end

  def position
    @detail = ScheduleByPositionReport.position(year: @year, position_id: @position.id)

    respond_to do |format|
      format.html
      format.csv do
        send_csv(csv_rows, filename: "#{@year}-#{@position.title.parameterize}-shifts.csv")
      end
    end
  end

  private

  def position_not_found_path
    scheduling_schedule_by_position_path(year: @year)
  end

  # One row per shift, in the order the page lists them.
  #
  # The position is a column rather than only a filename: upstream retitled the
  # description header to carry it, which says the same thing in a place a
  # spreadsheet cannot sort or filter on.
  def csv_rows
    rows = [["Position", "Description", "From", "To", "Active", "Sign-Ups", "Max", "Callsigns"]]

    @detail.shifts.each do |shift|
      slot = shift.slot
      rows << [@position.title, slot.description,
               slot.begins.iso8601, slot.ends.iso8601,
               slot.active ? "Y" : "N",
               shift.sign_ups.size, slot.max,
               shift.sign_ups.map(&:callsign).join(", ")]
    end

    rows
  end
end
