# frozen_string_literal: true

# Review a person's Missing Timesheet Entry requests: create a request on the
# person's behalf, review (approve/reject) a request, and optionally create the
# timesheet entry when approving. Ported from the Laravel
# TimesheetMissingController/TimesheetMissingPolicy and the Ember
# Person::TimesheetMissing component (staged in port/).
#
# Page access matches the person timesheets interface. Anyone with access may
# submit a new request on the person's behalf or view a request; reviewing
# (edit/update/destroy) requires Timesheet Management or Admin.
class Person::MissingRequestsController < ApplicationController
  layout "person"

  include PersonTimesheetConcern

  before_action :setup_entry, only: %i[show edit update destroy]

  authorize_ability :manage_timesheets,
                    roles: [Role::TIMESHEET_MANAGEMENT],
                    only: %i[edit update destroy],
                    deny_to: :timesheets_return_path,
                    message: "Timesheet Management role required to review missing timesheet requests."

  def show
  end

  def new
    build_position_options
    if @position_options.empty?
      return redirect_to timesheets_return_path,
                         error: "#{@person.callsign} has no positions granted. " \
                                "A missing timesheet request cannot be created."
    end

    @entry = TimesheetMissing.new(person_id: @person.id,
                                  position_id: default_position_id,
                                  review_status: TimesheetMissing::STATUS_PENDING)
  end

  def create
    @entry = TimesheetMissing.new(person_id: @person.id, create_person_id: current_user.id)
    @entry.assign_attributes(create_params)
    @entry.review_status = TimesheetMissing::STATUS_PENDING if @entry.review_status.blank?
    @entry.reviewer_person_id = current_user.id if @entry.review_status != TimesheetMissing::STATUS_PENDING

    if TimesheetMissingReview.save_and_maybe_create_entry(@entry, @person, current_user.id)
      redirect_to timesheets_return_path,
                  success: "Missing timesheet request created#{" and the timesheet entry added" if created_entry?}."
    else
      build_position_options
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    build_position_options
    prefill_new_entry_fields
    @next_pending = next_pending_request
  end

  # Port of the PHP TimesheetMissingController#update review flow.
  def update
    @entry.assign_attributes(update_params)

    @entry.reviewed_at = Current.time if @entry.review_status_changed?
    @entry.reviewer_person_id = current_user.id if current_user.id != @entry.person_id

    # A new note without a review decision puts the request back under review.
    if @entry.additional_notes.present? && !@entry.review_status_changed?
      @entry.review_status = TimesheetMissing::STATUS_PENDING
    end

    unless TimesheetMissingReview.save_and_maybe_create_entry(@entry, @person, current_user.id)
      build_position_options
      @next_pending = next_pending_request
      return render :edit, status: :unprocessable_entity
    end

    message = "The missing timesheet request has been updated#{" and the timesheet entry created" if created_entry?}."

    if params[:save_and_next].present? && (next_entry = next_pending_request)
      redirect_to edit_person_missing_request_path(@person, next_entry, year: @year), success: message
    else
      redirect_to timesheets_return_path, success: message
    end
  end

  def destroy
    @entry.destroy
    redirect_to timesheets_return_path, success: "Missing timesheet request deleted."
  end

  private

  def create_params
    permitted = %i[position_id on_duty off_duty partner additional_notes]
    permitted += %i[additional_wrangler_notes additional_admin_notes review_status create_entry] if can?(:manage_timesheets)
    params.expect(timesheet_missing: [*permitted])
  end

  def update_params
    params.expect(timesheet_missing: [:review_status, :create_entry,
                                      :new_on_duty, :new_off_duty, :new_position_id,
                                      :additional_notes, :additional_wrangler_notes,
                                      :additional_admin_notes])
  end

  def created_entry?
    @entry.status_approved? && @entry.create_entry
  end

  # Seed the "create new entry on approval" fields with the requested shift.
  def prefill_new_entry_fields
    @entry.new_on_duty ||= @entry.on_duty&.strftime("%Y-%m-%dT%H:%M")
    @entry.new_off_duty ||= @entry.off_duty&.strftime("%Y-%m-%dT%H:%M")
    @entry.new_position_id ||= @entry.position_id
  end

  # The next request still needing review, for the "Update & Review Next" flow.
  def next_pending_request
    TimesheetMissing.for_person(@person.id)
                    .for_year(@year)
                    .pending
                    .where.not(id: @entry.id)
                    .ordered_by_on_duty
                    .first
  end

  def default_position_id
    holds_dirt = @position_options.any? { |_title, id| id == Position::DIRT }
    holds_dirt ? Position::DIRT : @position_options.first[1]
  end

  # Dirt positions are offered first — they cover most missing shifts.
  def build_position_options
    dirt_positions = [Position::DIRT, Position::DIRT_POST_EVENT, Position::DIRT_GREEN_DOT]
    dirt, others = timesheet_position_options.partition { |_title, id| dirt_positions.include?(id) }
    @position_options = dirt + others
  end

  def setup_entry
    @entry = TimesheetMissing.includes(:position, :notes, :admin_notes)
                             .find_by(id: params[:id], person_id: @person.id)

    unless @entry
      redirect_to timesheets_return_path, error: "The missing timesheet request was not found."
      return false
    end

    @entry.check_times
    true
  end
end
