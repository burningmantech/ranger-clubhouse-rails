# frozen_string_literal: true

# Manage a person's timesheet entries for a year: review and correct entries,
# end an on-duty shift, confirm or un-confirm the entire timesheet, back-fill
# historical years rangered, and inspect the timesheet audit log and the
# hours/credits breakdown. Also hosts the person's shift check in/out page
# (/person/N/shift-manage) and its actions, via ShiftManageConcern.
#
# Ported from the Laravel TimesheetController/TimesheetPolicy and the Ember
# Person::TimesheetManage, TimesheetEditModal, TimesheetBackfill, and
# TimesheetLog components (staged in port/). Page access is declared by
# PersonTimesheetConcern; entry management requires Timesheet Management (or
# Admin), ending a shift requires Shift Management, and back-filling is Admin
# only.
class Person::TimesheetsController < ApplicationController
  layout "person"

  include PersonTimesheetConcern
  include ShiftManageConcern

  before_action :setup_years, only: %i[index log breakdown]
  before_action :setup_entry, only: %i[edit update destroy signoff]

  authorize_ability :manage_timesheets,
                    roles: [Role::TIMESHEET_MANAGEMENT],
                    only: %i[update destroy],
                    deny_to: :timesheets_return_path,
                    message: "Timesheet Management role required to manage timesheet entries."

  authorize_ability :sign_off,
                    roles: [Role::SHIFT_MANAGEMENT, Role::TIMESHEET_MANAGEMENT],
                    only: %i[signoff],
                    deny_to: :timesheets_return_path,
                    message: "Shift Management role required to end a shift."

  authorize_ability :manage_shifts,
                    roles: [Role::SHIFT_MANAGEMENT],
                    only: %i[shift_manage start_shift end_shift resignin correct_position update_position delete_mistake],
                    deny_to: :timesheets_return_path,
                    message: "Shift Management role required to check a person in or out of a shift."

  authorize_ability :confirm_timesheet,
                    roles: [Role::TIMESHEET_MANAGEMENT, Role::TECH_NINJA],
                    only: %i[confirm],
                    deny_to: :timesheets_return_path,
                    message: "Timesheet Management or Tech Ninja role required to confirm a timesheet."

  authorize_ability :backfill_timesheets,
                    only: %i[backfill create_backfill],
                    deny_to: :timesheets_return_path,
                    message: "Admin role required to back fill years rangered."

  BACKFILL_YEARS = (1996..2010)

  def index
    @timesheets = Timesheet.find_for_query(person_id: @person.id, year: @year, check_times: true).to_a
    @timesheets.sort_by! { |entry| [entry.status_pending? ? 0 : 1, entry.on_duty] }
    @overlapping_ids = overlapping_entry_ids(@timesheets)
    @missing_requests = TimesheetMissing.find_for_query(person_id: @person.id, year: @year)

    @entries_verified = @timesheets.count(&:status_verified?)
    @entries_unverified = @timesheets.count(&:verification_required?)
    @entries_pending = @timesheets.count(&:status_pending?)
    @missing_pending = @missing_requests.count(&:status_pending?)

    position_ids = (@timesheets.map(&:position_id) + @missing_requests.map(&:position_id)).uniq
    PositionCredit.warm_year_cache(@year, position_ids) if position_ids.any?

    # The stat row and the callouts above the table answer "what does this year
    # look like", so they are counted before any filter narrows anything -- a
    # reviewer who filters by position must not be told the year has no
    # corrections waiting. The rollups inside the entries section follow the
    # filter instead, because they describe the rows on screen.
    @filter_labels = timesheet_filter_labels
    @filters = timesheet_filters
    @filter_options = timesheet_filter_options
    @entries = filter_entries(@timesheets)

    @total_credits = @entries.sum(&:credits)
    @total_duration = @entries.sum(&:duration)
    @counted_duration = @entries.select { |entry| entry.position.count_hours }.sum(&:duration)

    @event = PersonEvent.first_or_new_for_person_year(@person.id, current_year) if @is_current_year
  end

  # Shift check in/out on its own page -- the panel shared with /me/shift-manage.
  def shift_manage
    load_shift_manage_state
  end

  def edit
    load_entry_logs
    build_position_options
    apply_desired_changes if params[:apply_desired].present?
  end

  def update
    @entry.assign_attributes(entry_params)

    if @entry.review_status_changed? || @entry.additional_wrangler_notes.present?
      @entry.reviewer_person_id = current_user.id
    end

    marked_unconfirmed = @entry.review_status_changed? && @entry.review_status != Timesheet::STATUS_VERIFIED

    unless save_entry(@entry)
      build_position_options
      load_entry_logs
      return render :edit, status: :unprocessable_entity
    end

    TimesheetManagement.unconfirm_timesheet(@entry, "marked #{@entry.review_status}") if marked_unconfirmed
    warn_of_overlaps(@entry)

    redirect_index(success: "Timesheet entry ##{@entry.id} updated.")
  end

  def destroy
    @entry.audit_reason = "timesheet deletion"
    @entry.destroy
    redirect_index(success: "Timesheet entry ##{@entry.id} deleted.")
  end

  # End an on-duty shift from the entries list. An inactive person going off
  # duty on a non-training, non-Cheetah-Cub shift is automatically converted
  # back to active status.
  #
  # Lands on the check in/out page, which shows the resulting duty state and
  # delivers the conversion as a modal (see ShiftManageConcern#end_shift). A
  # Timesheet Manager without Shift Management cannot open that page, so they
  # return to the entries list with the conversion in the toast instead.
  def signoff
    result = ShiftManage.sign_off(@entry, user: current_user)
    to_shift_page = can?(:manage_shifts)
    return_path = to_shift_page ? shift_return_path : timesheets_return_path

    if result.status == :already_signed_off
      return redirect_to return_path, error: "#{@person.callsign} was already signed off that shift."
    end

    message = "#{@person.callsign} has been signed off."
    if result.now_active && to_shift_page
      flash[:status_converted] = true
    elsif result.now_active
      message += " Status was automatically converted to Active."
    end

    redirect_to return_path, success: message
  end

  # Confirm or un-confirm the person's entire timesheet for the current year.
  # Only logged when the flag actually changes.
  def confirm
    confirmed = ActiveModel::Type::Boolean.new.cast(params[:confirmed])

    unless TimesheetManagement.set_confirmed_flag(@person.id, current_year, confirmed,
                                                  audit_reason: "timesheet confirm")
      return redirect_index(info: "The timesheet was already #{confirmed ? "confirmed" : "un-confirmed"}.")
    end

    TimesheetLog.record(confirmed ? TimesheetLog::CONFIRMED : TimesheetLog::UNCONFIRMED,
                        @person.id, current_user.id, nil, nil)

    redirect_index(success: "#{current_year} timesheet #{confirmed ? "confirmed" : "un-confirmed"}.")
  end

  def backfill
  end

  # Create a single verified Dirt entry to represent each selected historical
  # year. Years that already have any timesheet entry are skipped.
  def create_backfill
    years = Array(params[:years]).map(&:to_i).select { |year| BACKFILL_YEARS.cover?(year) }

    if years.empty?
      return redirect_to backfill_person_timesheets_path(@person), warning: "Select one or more years to back fill."
    end

    backfilled, skipped = years.sort.partition { |year| create_backfill_entry(year) }

    message = []
    message << "Back filled: #{backfilled.join(", ")}." if backfilled.any?
    message << "Skipped (entries already exist): #{skipped.join(", ")}." if skipped.any?
    redirect_index(success: message.join(" "))
  end

  # Timesheet audit log for the year — the PHP showLog grouping: entries with
  # their per-timesheet logs (deleted entries reconstructed from the log data),
  # plus the logs not tied to an entry (confirm/un-confirm and the like).
  def log
    timesheet_logs, @other_logs = TimesheetLog.find_for_person_year(@person.id, @year)
    @entries = group_logs_by_timesheet(timesheet_logs)
  end

  # Hours/credits breakdown by event period plus the per-position summary.
  def breakdown
    timesheets = Timesheet.find_for_query(person_id: @person.id, year: @year)
    @summary = EventSummaryReport.execute(@person.id, @year, rows: timesheets)
    @position_summary = PositionWorkSummary.execute(timesheets)
  end

  private

  # ShiftManageConcern contract
  def shift_person = @person

  def shift_self_serve? = false

  def shift_return_path = person_shift_manage_path(@person)

  def shift_start_path(**params) = start_shift_person_timesheets_path(@person, **params)

  def shift_end_path(**params) = end_shift_person_timesheets_path(@person, **params)

  def shift_resignin_path(**params) = resignin_person_timesheets_path(@person, **params)

  def shift_correct_position_path(**params) = correct_position_person_timesheets_path(@person, **params)

  def shift_delete_mistake_path(**params) = delete_mistake_person_timesheets_path(@person, **params)

  # Filters are normalized against the choices the page actually offers, so a
  # stale bookmark or a hand-edited URL lands on "all" rather than drawing a
  # chip claiming it narrowed something it did not.
  def timesheet_filters
    @filter_labels.to_h do |key, labels|
      [key, UiComponents::FilterBarHelper.known_filter(params[key], labels.keys)]
    end
  end

  def timesheet_filter_labels
    helpers.timesheet_filter_labels(@timesheets)
  end

  # Every filter, offered in full. A choice the rows cannot satisfy is drawn
  # disabled beside its zero rather than dropped: "Correction Requested (0)"
  # tells a reviewer there is nothing waiting, where a missing option teaches
  # nothing and leaves the panel rearranging itself between visits.
  #
  # Counts are narrowed by the OTHER filters but never by the select's own, or
  # every unchosen option in an applied select would read zero.
  def timesheet_filter_options
    @filter_labels.to_h do |key, labels|
      others = UiComponents::FilterBarHelper.active_filters(@filters.except(key))
      pool = @timesheets.select { |entry| entry_matches_filters?(entry, others) }
      counts = labels.keys.index_with { |value| pool.count { |entry| entry_matches_filter?(entry, key, value) } }

      [key, { choices: [UiComponents::FilterBarHelper::ALL_FILTER_OPTION] +
                       labels.map { |value, label| ["#{label} (#{counts[value]})", value] },
              disabled: counts.select { |_value, count| count.zero? }.keys }]
    end
  end

  def filter_entries(entries)
    active = UiComponents::FilterBarHelper.active_filters(@filters)
    return entries if active.empty?

    entries.select { |entry| entry_matches_filters?(entry, active) }
  end

  def entry_matches_filters?(entry, filters)
    filters.all? { |key, value| entry_matches_filter?(entry, key, value) }
  end

  def entry_matches_filter?(entry, key, value)
    helpers.timesheet_entry_matches?(entry, key, value, @overlapping_ids)
  end

  def entry_params
    permitted = params.expect(timesheet: [:on_duty, :off_duty, :position_id, :review_status,
                                          :is_echelon, :suppress_duration_warning,
                                          :additional_wrangler_notes, :additional_admin_notes])
    # A still on duty entry has no off duty time to correct.
    permitted = permitted.except(:off_duty, :review_status, :is_echelon, :suppress_duration_warning) if @entry.off_duty.nil?
    permitted
  end

  # The model's additional_notes validation is for the self-serve correction
  # flow (a requester note is mandatory there); reviewer edits are exempt, as
  # in the PHP controller.
  def save_entry(entry)
    entry.valid?
    entry.errors.delete(:additional_notes)
    return false if entry.errors.any?

    entry.save(validate: false)
  end

  def warn_of_overlaps(entry)
    return if entry.off_duty.nil?

    overlaps = Timesheet.find_all_overlaps_for_person(@person.id, entry.on_duty, entry.off_duty, entry.id)
    return if overlaps.empty?

    flash[:warning] = "The entry now overlaps in time with: " +
                      overlaps.map { |row| "#{row.position.title} #{datetime_range_for_flash(row)}" }.join(", ")
  end

  def datetime_range_for_flash(row)
    "#{row.on_duty.strftime(DateTimeHelper::MONTH_DAY_TIME)} - #{row.off_duty&.strftime("%H:%M")}"
  end

  def create_backfill_entry(year)
    return false if Timesheet.for_person(@person.id).for_year(year).exists?

    entry = Timesheet.new(
      person_id: @person.id,
      position_id: Position::DIRT,
      on_duty: Time.zone.local(year, 1, 1, 12, 0, 0),
      off_duty: Time.zone.local(year, 1, 1, 12, 1, 0),
      review_status: Timesheet::STATUS_VERIFIED,
      additional_admin_notes: "Back fill entry created to represent year #{year}",
      suppress_duration_warning: true
    )
    entry.audit_reason = "year back fill"
    entry.save!(validate: false)
    true
  end

  def group_logs_by_timesheet(rows)
    entries = {}

    rows.each do |row|
      entry = (entries[row.timesheet_id] ||= { timesheet_id: row.timesheet_id, logs: [] })

      if entry[:timesheet].nil? && row.timesheet
        entry[:timesheet] = {
          on_duty: row.timesheet.on_duty,
          off_duty: row.timesheet.off_duty,
          position_title: row.timesheet.position.title
        }
      end

      if row.action == TimesheetLog::DELETE
        data = row.decode_data || {}
        entry[:timesheet] = {
          on_duty: data["on_duty"],
          off_duty: data["off_duty"],
          position_title: data["position_title"] || "position not set"
        }
        entry[:deleted] = true
      end

      entry[:logs] << row
    end

    entries.values.sort_by { |entry| entry.dig(:timesheet, :on_duty).to_s.presence || "2099-01-01" }
  end

  # Ids of entries whose times overlap the (time-ordered) previous entry —
  # port of the Ember component's _markOverlapping.
  def overlapping_entry_ids(timesheets)
    ids = Set.new
    previous_end = nil
    previous_entry = nil

    timesheets.each do |entry|
      next if entry.off_duty.nil?

      if previous_end && entry.on_duty < previous_end
        ids << entry.id << previous_entry.id
      end
      previous_end = entry.off_duty
      previous_entry = entry
    end

    ids
  end

  # The entry's own position is always offered — the grant may have been
  # revoked since the shift happened.
  def build_position_options
    @position_options = timesheet_position_options

    unless @position_options.any? { |_title, id| id == @entry.position_id }
      @position_options.unshift([@entry.position.title, @entry.position_id])
    end
  end

  # Pre-fill the form with the person's requested changes ("Use the desired
  # changes" — assignment only, nothing is saved until the reviewer submits).
  def apply_desired_changes
    if @entry.desired_position_id.present?
      if @position_options.any? { |_title, id| id == @entry.desired_position_id }
        @entry.position_id = @entry.desired_position_id
      else
        flash.now[:warning] = "The desired position is not granted to #{@person.callsign} — it may have been " \
          "revoked after the correction was submitted. The position was not applied."
      end
    end

    @entry.on_duty = @entry.desired_on_duty if @entry.desired_on_duty.present?
    @entry.off_duty = @entry.desired_off_duty if @entry.desired_off_duty.present?
  end

  def load_entry_logs
    @entry_logs = @entry.timesheet_logs.includes(:creator).ordered
  end

  def setup_years
    @years = years_with_current(@person.years_combined || [])
  end

  def setup_entry
    @entry = Timesheet.includes(:position, :slot, :notes, :admin_notes, :verified_person)
                      .find_by(id: params[:id], person_id: @person.id)

    unless @entry
      redirect_index(error: "Timesheet entry not found.")
      return false
    end

    @entry.check_times
    true
  end

  def redirect_index(**flash_hash)
    redirect_to timesheets_return_path, **flash_hash
  end
end
