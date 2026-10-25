# frozen_string_literal: true

# HQ-scoped twin of the /me timesheet pages — a pseudo-management interface:
# the window operator reviews, verifies, and corrects the person's timesheet
# entries through the same self-serve flow the person has at /me, without
# needing the Timesheet Management role the real /person management page
# demands. See HqTimesheetConcern for the deliberate deviations from /me.
class Hq::TimesheetsController < ApplicationController
  include HqTimesheetConcern
  include TimesheetCorrectionsConcern

  def index
  end

  # Hours & credits breakdown — the /me "Event Summary" page, third person.
  def event_summary
    @summary = EventSummaryReport.execute(@person.id, @year, rows: @timesheets)
    @position_summary = PositionWorkSummary.execute(@timesheets)
  end
end
