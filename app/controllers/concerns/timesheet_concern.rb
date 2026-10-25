# frozen_string_literal: true

# Loads the timesheet data for a subject person and defines the contract the
# shared common/timesheet and common/missing_requests views render against.
#
# The default implementations below address the /me self-serve pages, where
# the subject is the signed-in person. HqTimesheetConcern overrides the
# contract to run the exact same flow at the HQ window, where the operator
# drives it on behalf of the person standing there.
module TimesheetConcern
  extend ActiveSupport::Concern

  included do
    # These pages offer the person's own history years (years_combined), which
    # reach back to 1995 -- below setup_year's 1998 default floor.
    self.year_floor = 1990
    before_action :setup_year
    before_action :setup_timesheets

    helper_method :timesheet_person, :timesheet_self_serve?, :timesheet_whose,
                  :timesheet_return_path, :timesheet_correction_path,
                  :timesheet_update_path, :timesheet_mark_verified_path,
                  :timesheet_event_summary_path, :timesheet_missing_requests_path,
                  :timesheet_new_missing_request_path,
                  :timesheet_edit_missing_request_path, :timesheet_missing_request_path
  end

  private

  def setup_timesheets
    @timesheets = Timesheet.find_for_query(person_id: timesheet_person.id, year: @year)
    @corrections_enabled = @is_current_year ? corrections_setting_enabled? : false

    if @is_current_year
      @timesheets_verified = @timesheets.count(&:status_verified?)
      @timesheets_unverified = @timesheets.count(&:verification_required?)
      @timesheets_pending = @timesheets.count(&:status_pending?)
      @timesheets_rejected = @timesheets.count(&:status_rejected?)
      @timesheets_approved = @timesheets.count(&:status_approved?)

      @missing_requests = TimesheetMissing.retrieve_for_person_or_all_for_year(timesheet_person.id, current_year)
      @missing_requests_count = @missing_requests.size
      @missing_requests_approved = @missing_requests.count(&:status_approved?)
      @missing_requests_rejected = @missing_requests.count(&:status_rejected?)
      @missing_requests_pending = @missing_requests.count(&:status_pending?)

      if @timesheets_unverified.positive? || @timesheets_pending.positive? || @missing_requests_pending.positive? || @missing_requests_rejected.positive?
        @have_outstanding = true
      else
        @have_outstanding = false
        @final_confirmation = PersonEvent.is_column_set?(timesheet_person.id, :timesheet_confirmed)
      end
    end

    true
  end

  # --- Subject & path contract: /me self-serve defaults ----------------------

  # Whose timesheet the pages operate on.
  def timesheet_person = current_user

  # True when the subject is driving their own pages; false at the HQ window,
  # which flips the shared views into third-person copy for the operator.
  def timesheet_self_serve? = true

  # Possessive for shared copy: "your credit earnings" / "Slats' credit earnings".
  def timesheet_whose
    timesheet_self_serve? ? "your" : "#{timesheet_person.callsign}'s"
  end

  # HQ overrides this to true: corrections are always available at the window.
  def corrections_setting_enabled? = setting(Setting::TIMESHEET_CORRECTION_ENABLE)

  # Where the entry actions land and forms cancel to — the timesheet dashboard.
  def timesheet_return_path = me_timesheet_dashboard_path

  def timesheet_correction_path(entry) = edit_me_timesheet_path(entry)

  def timesheet_update_path(entry) = me_timesheet_path(entry)

  def timesheet_mark_verified_path(entry) = mark_verified_me_timesheet_path(entry)

  def timesheet_event_summary_path = me_event_summary_path(year: @year)

  def timesheet_missing_requests_path = me_missing_requests_path

  def timesheet_new_missing_request_path = new_me_missing_request_path

  def timesheet_edit_missing_request_path(entry) = edit_me_missing_request_path(entry)

  def timesheet_missing_request_path(entry) = me_missing_request_path(entry)
end
