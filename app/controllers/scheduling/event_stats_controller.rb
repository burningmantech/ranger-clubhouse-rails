# frozen_string_literal: true

# How one year's event turned out: sign-ups against turnout, the Alpha cohort's
# outcomes, and how many people finished each training.
class Scheduling::EventStatsController < ApplicationController
  layout "scheduling"

  # Upstream TimesheetPolicy: the before hook admits Admin, and
  # eventStatsReport() admits Event Management. Deliberately narrower than the
  # scheduling reports beside it -- Edit Slots reads shift pages and has no
  # claim on the event's outcome, and Timesheet Management is not on this one
  # either.
  authorize_role [Role::ADMIN, Role::EVENT_MANAGEMENT],
                 message: "Admin or Event Management role required " \
                          "to view event statistics."

  # Upstream's own floor. A year the URL is allowed to ask for should be a year
  # the selector can show.
  self.year_floor = 2010

  before_action :setup_year

  def index
    @report = EventStatsReport.execute(year: @year)
  end
end
