# frozen_string_literal: true

# HQ flavor of the TimesheetConcern contract, shared by Hq::TimesheetsController
# and Hq::MissingRequestsController. The window operator drives the exact same
# self-serve flow the person has at /me — the same actions, no more — but the
# pages read as a management interface: third-person copy, no year selector,
# and every path stays inside the /hq shell.
#
# Deliberate deviations from /me, decided 2026-07-22:
#   * locked to the current year (the HQ shell has no year selector);
#   * corrections are always available — the TIMESHEET_CORRECTION_ENABLE
#     setting is not consulted at the window;
#   * only corrections, missing requests, and the hours & credits breakdown
#     exist here. Final confirmation stays a /me-only attestation, and
#     qualifications / work history keep their /me homes.
#
# HqConcern MUST be listed ahead of TimesheetConcern: inclusion order sets
# before_action order, so set_person has to run before setup_timesheets reads
# timesheet_person (see Hq::SchedulingController for the same rule). Both are
# module-level includes — ActiveSupport::Concern dependencies — NOT includes
# inside the included block: a base.include there would land the dependency
# closer to the controller class than this module, and TimesheetConcern's /me
# defaults would silently shadow every override below.
module HqTimesheetConcern
  extend ActiveSupport::Concern

  include HqConcern
  include TimesheetConcern

  included do
    before_action :require_subject_can_use_timesheets
  end

  private

  # --- TimesheetConcern contract ---------------------------------------------

  def timesheet_person = @person

  def timesheet_self_serve? = false

  def corrections_setting_enabled? = true

  def timesheet_return_path = hq_timesheets_path(@person)

  def timesheet_correction_path(entry) = edit_hq_timesheet_path(@person, entry)

  def timesheet_update_path(entry) = hq_timesheet_path(@person, entry)

  def timesheet_mark_verified_path(entry) = mark_verified_hq_timesheet_path(@person, entry)

  def timesheet_event_summary_path = event_summary_hq_timesheets_path(@person)

  def timesheet_missing_requests_path = hq_missing_requests_path(@person)

  def timesheet_new_missing_request_path = new_hq_missing_request_path(@person)

  def timesheet_edit_missing_request_path(entry) = edit_hq_missing_request_path(@person, entry)

  def timesheet_missing_request_path(entry) = hq_missing_request_path(@person, entry)

  # Locked to the current year, deliberately ignoring params[:year] — same
  # override as Hq::SchedulingController. Overrides ApplicationController#setup_year.
  def setup_year
    @year = Current.year
    @is_current_year = true
  end

  # Mirror of the /me status gate (TimesheetDashboardConcern's authorize_status),
  # applied to the person at the window rather than to the operator.
  def require_subject_can_use_timesheets
    return true if [*Person::ACTIVE_STATUSES, Person::ECHELON].include?(@person.status)

    redirect_to hq_shift_manage_path(@person),
                error: "#{@person.callsign} does not have an active status, so the timesheet pages are not available."
    false
  end
end
