# frozen_string_literal: true

# The self-serve missing-timesheet-request pages — list, submit, amend, appeal,
# and withdraw requests. Shared by Me::MissingRequestsController and
# Hq::MissingRequestsController; TimesheetConcern supplies the data and the
# subject/path contract. A request submitted at the HQ window still belongs to
# the person (person_id), while create_person_id records who typed it in.
module MissingRequestsConcern
  extend ActiveSupport::Concern

  included do
    before_action :are_corrections_enabled?
    before_action :setup_missing_request, only: [:edit, :update, :destroy]
    before_action :build_position_options, only: [:new, :create, :edit, :update]
  end

  def index
    @approved_requests, @unapproved_requests = @missing_requests.partition { |tm| tm.status_approved? }
  end

  def new
    @entry = TimesheetMissing.new(position_id: @position_options.first[1])
  end

  def create
    @entry = TimesheetMissing.new(missing_params)
    @entry.person_id = timesheet_person.id
    @entry.create_person_id = current_user.id
    @entry.review_status = TimesheetMissing::STATUS_PENDING
    if @entry.save
      flash[:success] = "Missing timesheet request submitted."
      redirect_to timesheet_missing_requests_path
    else
      render action: :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    @entry.assign_attributes(missing_params)
    @entry.review_status = TimesheetMissing::STATUS_PENDING
    if @entry.save
      flash[:success] = "Missing timesheet request updated."
      redirect_to timesheet_missing_requests_path
    else
      render action: :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @entry.destroy
    flash[:success] = "Missing timesheet request deleted."
    redirect_to timesheet_missing_requests_path
  end

  private

  def missing_params
    params.expect(timesheet_missing: [:position_id, :on_duty, :off_duty, :partner, :additional_notes])
  end

  def are_corrections_enabled?
    return true if corrections_setting_enabled?

    flash[:error] = "Timesheet corrections are not enabled."
    redirect_to timesheet_return_path
    false
  end

  def build_position_options
    options = PersonPosition.retrieve_all_for_person(timesheet_person, include_eligibility: true, include_past_grants: true).map { |p| [p.title, p.id] }
    dirt_positions = [Position::DIRT, Position::DIRT_POST_EVENT, Position::DIRT_GREEN_DOT]
    dirt_shifts, other_shifts = options.partition { |opt| dirt_positions.include?(opt[1]) }
    @position_options = dirt_shifts + other_shifts
  end

  def setup_missing_request
    @entry = TimesheetMissing.find_by(id: params[:id])
    unless @entry && @entry.person_id == timesheet_person.id
      flash[:error] = "The missing timesheet request was not found."
      redirect_to timesheet_missing_requests_path
      return false
    end

    if @entry.review_status == TimesheetMissing::STATUS_APPROVED
      flash[:error] = "The missing timesheet request was approved. No further updates are allowed."
      redirect_to timesheet_missing_requests_path
      return false
    end

    true
  end
end
