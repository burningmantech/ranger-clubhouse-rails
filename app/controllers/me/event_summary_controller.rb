# frozen_string_literal: true

class Me::EventSummaryController < ApplicationController
  include TimesheetDashboardConcern
  include TimesheetConcern

  layout "me"

  def index
    @summary = EventSummaryReport.execute(current_user.id, @year, rows: @timesheets)
    @position_summary = PositionWorkSummary.execute(@timesheets)
  end
end
