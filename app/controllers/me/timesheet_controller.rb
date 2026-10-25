class Me::TimesheetController < ApplicationController
  include TimesheetDashboardConcern
  include TimesheetConcern
  include TimesheetCorrectionsConcern
  include QualificationsConcern

  layout "me/timesheet"

  before_action :are_corrections_enabled?, only: [:final_confirmation, :final_confirmation_acknowledgement]
  before_action :no_pending_tasks, only: [:final_confirmation, :final_confirmation_acknowledgement]
  before_action :set_person, only: [:qualifications]
  before_action :set_back_to, only: [:qualifications]

  def index
    @show_confirm_warning = true
  end

  def final_confirmation
  end

  def final_confirmation_acknowledgement
    person_event = PersonEvent.first_or_new_for_person_year(current_user.id, current_year)
    person_event.timesheet_confirmed = true
    person_event.timesheet_confirmed_at = Current.time
    person_event.save(validate: false)
    TimesheetLog.record(TimesheetLog::CONFIRMED, current_user.id, current_user.id, nil, nil)
    flash[:success] = "Timesheet confirmed as accurate."
    redirect_to me_timesheet_index_path
  end

  private

  # Verifying the final unverified entry continues into final confirmation.
  def all_verified_redirect_path = final_confirmation_me_timesheet_index_path

  def no_pending_tasks
    unless Timesheet.count_unverified_for_person_year(current_user.id, current_year) == 0
      flash[:error] = "There are still unfinished tasks to perform."
      redirect_to me_timesheet_index_path
      return false
    end
    true
  end

  # QualificationsConcern reads @person; the timesheet concerns go through
  # timesheet_person instead, so nothing else here had set it.
  def set_person
    @person = current_user
  end

  def set_back_to
    @back_to_url = me_timesheet_dashboard_path(year: @year)
    @back_to_label = "Timesheet"
    @signups_url = me_available_sign_up_path
  end
end
