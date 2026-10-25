# frozen_string_literal: true

# Timesheet entries linked to the wrong scheduled shift (Ember
# admin/timesheet-slot-repair port). Upstream rewrote every entry it disagreed
# with the moment the button was pressed; this shows the changes first and
# writes only the ones picked.
class Timesheets::TimesheetSlotRepairController < ApplicationController
  layout "timesheets"

  # Upstream's Ember route asks for Tech Ninja, but TimesheetPolicy grants
  # Admin and Timesheet Management and refuses everyone else -- a Tech Ninja
  # reached the page and was turned away by the button on it. The API is the
  # authority, so the page, the menu link, and the write all agree with it.
  #
  # One gate covers both: a reader who can see these entries can settle them.
  authorize_role [Role::ADMIN, Role::TIMESHEET_MANAGEMENT],
                 message: "Admin or Timesheet Management role required to repair " \
                          "timesheet shift links."

  # Upstream's client-side floor. Left at the 1998 default, a year the URL is
  # allowed to ask for is a year the selector cannot show, and picking it back
  # fires no change event.
  self.year_floor = 2010

  before_action :setup_year

  def index
    load_changes
  end

  # Relink the selected entries and show what happened.
  #
  # Renders rather than redirects, and at 422 so Turbo accepts it: what the
  # repair did is not something a fresh load can re-derive once the entries it
  # fixed have stopped needing repair.
  def apply
    @results, @skipped = TimesheetSlotRepair.apply(@year, params.permit(timesheet_ids: [])[:timesheet_ids])
    load_changes

    render :index, status: :unprocessable_entity
  end

  private

  def load_changes
    @scanned, @changes = TimesheetSlotRepair.scan(@year)
    @groups = @changes.group_by(&:kind)
  end
end
