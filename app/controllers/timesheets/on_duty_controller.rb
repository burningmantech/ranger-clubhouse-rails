# frozen_string_literal: true

# Who is on duty (Ember reports/on-duty port).
#
# Deliberately NOT year-scoped in the year-selector sense: with no duty date
# the question is "who is out right now", and with one the year is whatever the
# duty date says. A year selector would only be able to disagree with it.
class Timesheets::OnDutyController < ApplicationController
  layout "timesheets"

  # Timesheet Management is carried over from upstream's TimesheetPolicy::before
  # hook, which grants that role every method on the policy, this report
  # included. person_timesheet_concern and work_history spell the same three.
  authorize_role [Role::ADMIN, Role::EVENT_MANAGEMENT, Role::TIMESHEET_MANAGEMENT],
                 message: "Admin, Event Management, or Timesheet Management role required " \
                          "to see who is on duty."

  def index
    @duty_date = parse_duty_date
    # Named at call time, not in the class body: a load-time reference from a
    # controller to its helper is how autoload cycles start.
    @excessive_only = params[:excessive_only] == Timesheets::OnDutyHelper::ON

    @report = OnDutyReport.execute(duty_date: @duty_date, excessive_only: @excessive_only)

    # A duty date that could not be read is dropped from the chips and from
    # every URL built off them -- it is not filtering anything.
    @filter_params = { duty_date: (@duty_date ? params[:duty_date] : nil),
                       excessive_only: (@excessive_only ? Timesheets::OnDutyHelper::ON : nil) }
  end

  private

  # Upstream validates duty_date as a `date` and 422s anything it cannot read.
  # This page gets opened at 3am to find someone who is still out there; a bad
  # value in the URL must not be what stops it, so it falls back to "right now"
  # and says so.
  def parse_duty_date
    raw = params[:duty_date]
    return if raw.blank?

    # duty_date is never permitted, so `?duty_date[a]=b` hands us an
    # ActionController::Parameters and `?duty_date[]=1` an Array. Neither
    # answers the String methods below, and the NoMethodError would 500 the
    # page this method exists to keep alive.
    return bad_duty_date unless raw.is_a?(String)

    # Time.zone.parse fills in whatever the string leaves out, so it reads
    # "the 3rd shift" as the 3rd of this month and "next tuesday at 3" as today
    # at midnight -- then the page states that instant as fact. Demand a whole
    # calendar date instead; a digit test let every one of those through.
    return bad_duty_date(raw) unless Date._parse(raw).values_at(:year, :mon, :mday).all?

    Time.zone.parse(raw) || bad_duty_date(raw)
  rescue ArgumentError
    bad_duty_date(raw)
  end

  # :warning, not :alert -- ToastHelper::TOAST_TYPES has no :alert key, so that
  # fell back to the blue :info styling and read as an FYI rather than as the
  # page having ignored what was asked for.
  def bad_duty_date(raw = nil)
    quoted = raw.is_a?(String) ? " #{raw.inspect}" : ""
    flash.now[:warning] = "Could not read#{quoted} as a date and time. " \
                          "Showing who is on duty right now."
    nil
  end
end
