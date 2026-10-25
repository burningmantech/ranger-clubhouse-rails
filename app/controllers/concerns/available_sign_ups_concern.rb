# frozen_string_literal: true

module AvailableSignUpsConcern
  extend ActiveSupport::Concern

  included do
    # The schedule pages link here carrying their year, and their selector
    # offers the person's own history years (years_combined), which reach back
    # to 1995 -- below setup_year's 1998 default floor.
    self.year_floor = 1990
    before_action :ensure_person_for_available_sign_ups
    before_action :setup_year
    before_action :retrieve_permission_and_recommendation
    before_action :setup_position, only: [:show, :create, :destroy]
    before_action :setup_slot, only: [:create, :destroy]

    helper_method :prevent_training_signup?
  end

  def index
    @entries, @positions = Scheduling::Query.find_for_query(@person.id, @year, no_credits: true)
  end

  def show
    # Without the Online Course the Training page is a preview: a warning, then
    # the sessions by month and description only -- no dates, seats or buttons.
    @training_locked = prevent_training_signup?(@position.id)

    entries, _ = Scheduling::Query.find_for_query(@person.id, @year, position_id: @position.id)
    @upcoming_entries, @past_entries = Scheduling::Query.partition_by_time(entries, cutoff: :start_time)

    @signup_count = @upcoming_entries.count { |s| s.person_assigned }
    @overlapping_entries = @upcoming_entries.filter { |s| s.person_assigned && s.is_overlapping }
    @overlapping_count = @overlapping_entries.size
    @non_overlapping_count = @signup_count - @overlapping_count

    @is_training = (@position.id == Position::TRAINING)
    @is_alpha_position = (@position.id == Position::ALPHA)
    @show_training_advisory = @is_training && @is_current_year && !@training_locked

    # Logic for full day training requirement
    @needs_full_training = false
    if @is_training
      @needs_full_training, _ = Training.requires_training_full_day?(@person)
    end

    @person_status = @person.status
    # The subject's status, not the viewer's: on /person and /hq an operator
    # sees what the member sees. A note about signing up has nothing to say
    # above a past year's shifts (ruled 2026-10-22).
    @scheduling_header = @position.scheduling_header_for(@person) if @is_current_year
  end

  def create
    @result = Scheduling::Signup.add(@person, @slot, false)
    @entries, _ = Scheduling::Query.find_for_query(@person.id, @year, position_id: @position.id)

    case (verdict = @result.verdict)
    when Scheduling::Verdict::Accepted
      @message = "Shift added."
      @status = :success
      if @slot.url.present? ||
          (verdict.linked_slots_became_full && verdict.linked_slots&.any?) ||
          verdict.mvr
        @modal = "common/scheduling/slot_additional_info_modal"
      end
    when Scheduling::Verdict::OutsideWindow
      @message = "The shift has #{verdict.ended ? "ended" : "started"}"
      @status = :error
    when Scheduling::Verdict::AlreadyExists
      @message = "The shift was previously added."
      @status = :warning
    when Scheduling::Verdict::Full
      @message = "Sorry, the shift has become full."
      @status = :error
    when Scheduling::Verdict::MissingRequirements
      @modal = "common/scheduling/missing_requirements_modal"
    when Scheduling::Verdict::MultipleEnrollment
      @modal = "common/scheduling/multiple_enrollment_modal"
    else
      @message = "Unknown status [#{@result.status}]"
      @status = :error
    end

    respond_to do |format|
      format.turbo_stream
    end
  end

  def destroy
    result = Scheduling::Signup.remove(@person, @slot, true)
    @entries, _ = Scheduling::Query.find_for_query(@person.id, @year, position_id: @position.id)
    case (verdict = result.verdict)
    when Scheduling::Verdict::Removed
      @message = "Shift removed."
      @status = :success
    when Scheduling::Verdict::OutsideWindow
      @message = "The shift has #{verdict.ended ? "ended" : "started"} and cannot be removed from the schedule."
      @status = :error
    when Scheduling::Verdict::MissingSignup
      @message = "The shift was not signed up for."
      @status = :error
    else
      @message = "Unknown status [#{result.status}]"
      @status = :error
    end

    respond_to do |format|
      format.turbo_stream
    end
  end

  private

  def ensure_person_for_available_sign_ups
    @person ||= current_user
  end

  def prevent_training_signup?(id)
    @is_current_year && id == Position::TRAINING && !@signup_permission.training_signups_allowed
  end

  def retrieve_permission_and_recommendation
    if @is_current_year
      @signup_permission = Scheduling::Permission.new(@person, @year)
      if @signup_permission.requirements.any?
        redirect_to schedule_redirect_path(year: @year), error: "One or more sign-up requirements have not been met."
        return false
      end
    end
    true
  end

  def setup_position
    position_id = params.expect!(:position_id).to_i
    unless (@position = Position.find_by(id: position_id))
      redirect_to sign_ups_redirect_path, error: "The position ##{position_id} does not exist."
      return false
    end

    unless PersonPosition.have_position?(@person.id, position_id)
      redirect_to sign_ups_redirect_path, error: "You do not hold that position."
      return false
    end
    true
  end

  def setup_slot
    slot_id = params.expect!(:slot_id).to_i
    unless (@slot = Slot.find_by(id: slot_id))
      redirect_to sign_ups_position_redirect_path(@position.id), error: "The slot ##{slot_id} was not found."
      return false
    end

    unless @slot.position_id == @position.id
      redirect_to sign_ups_position_redirect_path(@position.id), error: "The slot ##{slot_id} does not belong to position ##{@position.id}."
      return false
    end

    unless @slot.active
      redirect_to sign_ups_position_redirect_path(@position.id), error: "The slot ##{slot_id} has not been activated."
      return false
    end

    unless @slot.begins_year == @year
      redirect_to sign_ups_position_redirect_path(@position.id), error: "The slot ##{slot_id} is not for the selected year (#{@year})."
      return false
    end

    true
  end
end
