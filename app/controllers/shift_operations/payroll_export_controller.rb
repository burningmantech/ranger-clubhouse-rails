# frozen_string_literal: true

# Timesheet entries for a pay period, and the punch files payroll loads.
#
# The page and all four downloads are one GET: the window, the positions, and
# the meal-break rules live in the query string, so an export link is simply the
# page's own address with a format and a variant on the end. That keeps a
# download and the table it came from describing the same set of entries, and
# lets a clerk bookmark or re-send a pay period.
class ShiftOperations::PayrollExportController < ApplicationController
  include CsvExportConcern

  layout "shift_operations"

  authorize_role [Role::ADMIN, Role::PAYROLL],
                 message: "Payroll role required to export timesheet entries for payroll."

  # The Ranger department, which every punch is booked against.
  DEPARTMENT_CODE = "660"

  # Punched in and out for the day, and out to and back from a meal. A shift cut
  # in two is punched in for the day, out to lunch, back from lunch, then out
  # for the day.
  PUNCH_IN_DAY = "ID"
  PUNCH_OUT_DAY = "OD"
  PUNCH_IN_LUNCH = "IL"
  PUNCH_OUT_LUNCH = "OL"

  PUNCH_HEADER = ["Employee No.", "Department", "Date", "Punch Time", "Punch Type",
                  "Rate Type", "Leave Blank", "Punch Comment", "Sub-Department",
                  "Leave Blank", "Leave Blank", "Rate"].freeze

  TABLE_HEADER = ["Callsign", "First Name", "Last Name", "Employee ID", "Position",
                  "Paycode", "Entry Status", "Orig Start", "Orig End", "Duration",
                  "First Half Start", "First Half End", "Second Half Start",
                  "Second Half End", "Notes"].freeze

  # Every export flavour this page can hand back, and the word each one puts in
  # its filename. Spelled once so an unknown variant cannot be renamed into
  # looking like the file that was actually asked for.
  VARIANTS = %w[adjusted unadjusted table without-ids].freeze
  DEFAULT_VARIANT = "adjusted"

  def index
    @positions = payroll_positions
    @form = build_form
    @report = run_report if submitted? && @form.valid?

    respond_to do |format|
      format.html
      format.csv { send_export }
    end
  end

  private

  # Only positions that are paid and still in use can be reported on -- a
  # position with no paycode has nowhere to land in the payroll system.
  def payroll_positions
    Position.active.with_paycode.order(:paycode, :title)
  end

  def build_form
    return PayrollExportForm.with_defaults(position_ids: @positions.map(&:id)) unless submitted?

    PayrollExportForm.new(form_params)
  end

  def submitted? = form_params.present?

  def form_params
    @form_params ||= scoped_params(PayrollExportForm::PARAM_SCOPE, :start_time, :end_time, :break_after,
                                   :break_duration, :person_id, position_ids: [])
  end

  def run_report
    report = full_report
    # The picker has to keep offering everyone. Built from the narrowed report
    # it would collapse to whoever is already chosen, and switching from one
    # person to another would mean going back through "Everyone" each time.
    @roster = report.people
    report.for_person(@form.person_id)
  end

  def full_report
    PayrollExportReport.execute(start_time: @form.parsed_start_time,
                                end_time: @form.parsed_end_time,
                                break_after_hours: @form.break_after_hours,
                                break_duration_minutes: @form.break_duration_minutes,
                                # Narrowed to what this page offers. The ids ride
                                # in the query string, so an old bookmark can name
                                # a position since retired or stripped of its
                                # paycode -- whose hours would reach the file with
                                # nothing to book them against.
                                position_ids: @form.position_ids & @positions.map(&:id))
  end

  # A download only makes sense once the report has run. Anything else lands on
  # the page carrying whatever was asked for, so a bookmark that has gone stale
  # -- a period now longer than the cap, positions since retired -- arrives at
  # the reason rather than at an empty form.
  def send_export
    if @report.nil?
      carried = submitted? ? @form.query_params : {}
      return redirect_to(shift_operations_payroll_export_path(carried))
    end

    variant = VARIANTS.include?(params[:variant]) ? params[:variant] : DEFAULT_VARIANT

    send_csv(export_for(variant), filename: "payroll-#{@form.window_slug}-#{variant}.csv")
  end

  def export_for(variant)
    case variant
    when "unadjusted" then punch_rows(@report.people, adjusted: false)
    when "table" then table_rows(@report.people)
    when "without-ids" then punch_rows(@report.people_without_ids, adjusted: true)
    else punch_rows(@report.people, adjusted: true)
    end
  end

  # The punch file payroll reads. Every shift becomes a pair of rows, or two
  # pairs when a meal break cut it in two.
  #
  # Unadjusted means the times as they were recorded: no clipping to the pay
  # window and no meal break. It is there for the pay period where the clipped
  # answer is wrong and a person would rather fix it downstream.
  def punch_rows(people, adjusted:)
    rows = [PUNCH_HEADER]

    people.each do |person|
      person.shifts.each do |shift|
        if !adjusted
          rows.concat(punch_pair(person, shift, shift.orig_on_duty, shift.orig_off_duty,
                                 PUNCH_IN_DAY, PUNCH_OUT_DAY))
        elsif shift.split?
          meal = shift.meal_break
          rows.concat(punch_pair(person, shift, meal.first_on_duty, meal.first_off_duty,
                                 PUNCH_IN_DAY, PUNCH_OUT_LUNCH))
          rows.concat(punch_pair(person, shift, meal.second_on_duty, meal.second_off_duty,
                                 PUNCH_IN_LUNCH, PUNCH_OUT_DAY))
        else
          rows.concat(punch_pair(person, shift, shift.on_duty, shift.off_duty,
                                 PUNCH_IN_DAY, PUNCH_OUT_DAY))
        end
      end
    end

    rows
  end

  # The in row carries who, where, and why; the out row only has to close it.
  def punch_pair(person, shift, on_duty, off_duty, in_code, out_code)
    [
      [person.employee_id, DEPARTMENT_CODE, punch_date(on_duty), punch_time(on_duty), in_code,
       "", "", "#{person.callsign} - #{shift.position_title}", shift.paycode, "", "", ""],
      [person.employee_id, "", punch_date(off_duty), punch_time(off_duty), out_code,
       "", "", "", "", "", "", ""]
    ]
  end

  def punch_date(time) = time.strftime("%Y-%m-%d")

  def punch_time(time) = time.strftime("%H:%M")

  # A plain dump of what the page shows, for checking against by hand. Not a
  # format the payroll system takes.
  def table_rows(people)
    rows = [TABLE_HEADER]

    people.each do |person|
      record = person.record

      person.shifts.each do |shift|
        meal = shift.meal_break

        rows << [person.callsign, record.first_name, record.last_name, person.employee_id,
                 shift.position_title, shift.paycode, shift.status_label,
                 punch_datetime(shift.orig_on_duty), punch_datetime(shift.orig_off_duty),
                 helpers.hour_minute_format(shift.orig_duration),
                 punch_datetime(meal ? meal.first_on_duty : shift.on_duty),
                 punch_datetime(meal ? meal.first_off_duty : shift.off_duty),
                 punch_datetime(meal&.second_on_duty),
                 punch_datetime(meal&.second_off_duty),
                 shift.notes_text]
      end
    end

    rows
  end

  def punch_datetime(time) = time ? time.strftime(DateTimeHelper::CSV_TIME) : ""
end
