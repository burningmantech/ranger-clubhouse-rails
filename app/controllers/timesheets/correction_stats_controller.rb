# frozen_string_literal: true

# One year of correction activity, counted (Ember reports/timesheet-correction-stats
# port). The sibling Correction Requests page lists what is still waiting; this
# one measures what has already been decided.
class Timesheets::CorrectionStatsController < ApplicationController
  layout "timesheets"

  # Upstream TimesheetPolicy: the before hook admits Admin and Timesheet
  # Management, and correctionStatistics() is a hard false, adding no one. The
  # same gate as Correction Requests and Early / Late Check-Ins.
  authorize_role [Role::ADMIN, Role::TIMESHEET_MANAGEMENT],
                 message: "Admin or Timesheet Management role required " \
                          "to view timesheet correction statistics."

  # Upstream's own floor. A year the URL is allowed to ask for should be a year
  # the selector can show.
  self.year_floor = 2018

  before_action :setup_year

  def index
    @report = CorrectionStatsReport.execute(year: @year)
  end
end
