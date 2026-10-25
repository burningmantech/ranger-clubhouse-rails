# frozen_string_literal: true

# The self-serve timesheet correction actions — verify an entry, and request /
# appeal a correction. Shared by Me::TimesheetController (the person acting for
# themselves) and Hq::TimesheetsController (the window operator acting on the
# person's behalf); TimesheetConcern supplies the data and the subject/path
# contract the actions and views run against.
module TimesheetCorrectionsConcern
  extend ActiveSupport::Concern

  included do
    before_action :are_corrections_enabled?, only: [:mark_verified, :edit, :update]
    before_action :setup_entry, only: [:mark_verified, :edit, :update]
    before_action :setup_entries
  end

  def mark_verified
    @entry.review_status = Timesheet::STATUS_VERIFIED
    @entry.save(validate: false)
    if Timesheet.count_unverified_for_person_year(timesheet_person.id, current_year) == 0
      render turbo_stream: turbo_stream.page_redirect(all_verified_redirect_path)
    else
      render turbo_stream: turbo_stream.update("entry-#{@entry.id}",
                                               partial: "common/timesheet/entry_with_action",
                                               locals: { entry: @entry })
    end
  end

  def edit
    build_desired_position_options
  end

  def update
    entry_params = params.expect(timesheet: [:desired_position_id, :desired_on_duty, :desired_off_duty,
                                             :additional_notes])

    @entry.review_status = Timesheet::STATUS_PENDING
    @entry.assign_attributes entry_params

    if @entry.save
      TimesheetManagement.unconfirm_timesheet(@entry, "correction submitted")
      flash[:success] = "Correction request submitted."
      redirect_to timesheet_return_path
    else
      build_desired_position_options
      render action: :edit, status: :unprocessable_entity
    end
  end

  private

  # Where verifying the final unverified entry lands. Defaults to the entries
  # list; /me overrides it to continue into the final confirmation step, which
  # is deliberately a /me-only attestation (the HQ window has no equivalent).
  def all_verified_redirect_path = timesheet_return_path

  def are_corrections_enabled?
    return true if @corrections_enabled

    flash[:error] = "Timesheet corrections and verification is not available."
    redirect_to timesheet_return_path
    false
  end

  def setup_entry
    id = params.expect!(:id).to_i
    @entry = @timesheets.find { |entry| entry.id == id }
    unless @entry
      flash[:error] = "Timesheet entry not found."
      redirect_to timesheet_return_path
      return false
    end

    unless @entry.off_duty
      flash[:error] = "The shift is still going. Once the shift has ended, the entry can be corrected."
      redirect_to timesheet_return_path
      return false
    end

    true
  end

  def build_desired_position_options
    @desired_position_options = PersonPosition.retrieve_all_for_person(timesheet_person, include_eligibility: true, include_past_grants: true).map { |p| [p.title, p.id] }
    @desired_position_options.unshift(["#{@entry.position.title} is correct", nil])
  end

  def setup_entries
    @unverified_entries = @timesheets.filter(&:verification_required?)
    @verified_entries = @timesheets.filter(&:status_verified?)
    @pending_entries = @timesheets.filter(&:status_pending?)
  end
end
