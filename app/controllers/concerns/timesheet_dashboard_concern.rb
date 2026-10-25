module TimesheetDashboardConcern
  extend ActiveSupport::Concern

  included do
    attr_accessor :show_confirm_warning

    include ActionView::Helpers::UrlHelper

    helper_method :back_to_timesheet_dashboard

    authorize_status [*Person::ACTIVE_STATUSES, Person::ECHELON]
  end

  private

  def set_show_confirm_warning
    @show_confirm_warning = true
  end

  def back_to_timesheet_dashboard(year = nil)
    back_to "Timesheet", (year ? me_timesheet_dashboard_path(year:) : me_timesheet_dashboard_path)
  end
end
