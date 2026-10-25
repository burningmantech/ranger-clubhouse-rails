# frozen_string_literal: true

# Shared plumbing for the person timesheet administration pages
# (Person::TimesheetsController and Person::MissingRequestsController).
#
# Access mirrors the Laravel TimesheetPolicy#index: Event Management,
# Timesheet Management, or Admin — the broader person-page roles (Mentor,
# Trainer, VC) do not have timesheet access.
module PersonTimesheetConcern
  extend ActiveSupport::Concern

  included do
    include PersonConcern

    authorize_role [Role::ADMIN, Role::EVENT_MANAGEMENT, Role::TIMESHEET_MANAGEMENT],
                   message: "Event Management or Timesheet Management role required to view timesheets."

    # These pages offer the person's own history years (years_combined), which
    # reach back to 1995 -- below setup_year's 1998 default floor.
    self.year_floor = 1990
    before_action :setup_year
  end

  private

  # Options for the positions the person may hold a timesheet for.
  def timesheet_position_options
    PersonPosition.retrieve_all_for_person(@person, include_past_grants: true)
                  .reject(&:not_timesheet_eligible)
                  .map { |position| [position.title, position.id] }
  end

  # Where timesheet pages return to — also the deny target for ability gates.
  def timesheets_return_path
    person_timesheets_path(@person, year: @year)
  end
end
