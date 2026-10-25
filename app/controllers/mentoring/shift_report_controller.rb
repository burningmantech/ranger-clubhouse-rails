# frozen_string_literal: true

# The Mentor Shift Report (upstream Ember mentor/shift-report off
# MentorController::shiftReport and MentorShiftReport.php). Pick one of a
# year's Alpha shifts to see who is signed up across every mentor-family
# position in the surrounding time window, or flip to who is on duty right
# now. Read-only.
#
# Deliberate departures from upstream, settled when this page was specced
# (see .scratch/mentoring-shift-report/PLAN.md):
#
#   * A shift with zero sign-ups renders a "No sign-ups yet" line and counts
#     toward the Unfilled shifts stat, instead of upstream's nothing-at-all --
#     an empty shift next to the Alpha shift is exactly what a Mentor Lead
#     opens this report to catch.
#   * The first year-scoped /mentoring page: the year selector picks which
#     year's Alpha shifts fill the dropdown. On-duty mode ignores the year and
#     always reads the current year, as upstream does; the banner says so.
class Mentoring::ShiftReportController < ApplicationController
  layout "mentoring"

  before_action :setup_year

  # Upstream Gate isMentor.
  authorize_role [Role::ADMIN, Role::MENTOR],
                 message: "Admin or Mentor role required to view the shift report."

  # The year selector's floor, matching upstream's YearSelect minYear.
  self.year_floor = 2010

  def index
    if params[:on_duty].present?
      @report = MentorShiftReport.on_duty
    elsif params[:slot_id].present?
      load_slot_report
    end

    # The picker is the Alpha Schedule's card grid, so a mentor lead sees the
    # same shifts described the same way on both pages. Only loaded when no
    # report is on screen -- the report replaces the picker.
    @shifts = pickable_shifts if @report.nil?
  end

  private

  # Inactive shifts are dropped rather than badged (the Alpha Schedule keeps
  # them): the report's window query is active-only, so an inactive card would
  # open a report the shift never appears in.
  def pickable_shifts
    AlphaShiftRoster.shifts_for_year(@year).select { |shift| shift.slot.active }
  end

  # Upstream 422s on a slot that is missing or not the Alpha position; here a
  # bad id keeps the picker on screen with an error. The slot is looked up
  # across all years on purpose -- the report runs on the slot's own year, and
  # a bookmarked link must keep meaning the same shift whatever the selector
  # currently shows. Inactive slots fall through to the error: the window
  # query is active-only, so an inactive shift would banner a report it then
  # never appears in.
  def load_slot_report
    slot = Slot.active.where(position_id: Position::ALPHA).find_by(id: params[:slot_id])
    unless slot
      flash.now[:error] = "That shift is not an Alpha shift this report covers. Pick a shift from the list."
      return
    end

    @report = MentorShiftReport.for_slot(slot)
  end
end
