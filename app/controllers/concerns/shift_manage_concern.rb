# frozen_string_literal: true

# Shift check in/out actions shared by the self-serve page
# (Me::ShiftManageController) and the admin person shift-manage page
# (Person::TimesheetsController). The command logic lives in ShiftManage;
# this concern maps its result statuses onto redirects (terminal outcomes)
# and turbo-stream modals (interstitials: blockers, too-short shift,
# position correction). Shared templates live in app/views/common/shift_manage/.
#
# Includers must define (exposed to the shared views as helper methods):
#   shift_person                - the Person being checked in or out
#   shift_self_serve?           - true when the person manages their own shifts
#   shift_return_path           - where redirects land
#   shift_start_path            - POST target to start a shift
#   shift_end_path              - POST target to end a shift
#   shift_resignin_path         - POST target to resume an accidentally ended shift
#   shift_correct_position_path - GET renders the correction modal, PATCH applies it
#   shift_delete_mistake_path   - DELETE target for an accidental entry
#
# Includers may override allow_correction_on_end? (default false) to offer
# "End Shift & Submit Correction" on the on-duty panel. It only works where the
# return path can re-open the correction modal for the just-ended entry, which
# today is the HQ Window alone (upstream @allowCorrectionOnEnd).
#
# A successful start or end sets @shift_transition (:started / :ended) before
# redirecting. Includers whose return path encodes "a shift was just handled"
# in the URL read it there; every failure leaves it nil, so a refused check-in
# cannot redirect as though one had happened.
module ShiftManageConcern
  extend ActiveSupport::Concern

  included do
    helper_method :shift_person, :shift_self_serve?, :shift_return_path,
                  :shift_start_path, :shift_end_path, :shift_resignin_path,
                  :shift_correct_position_path, :shift_delete_mistake_path,
                  :shift_can_force?, :shift_positions, :allow_correction_on_end?
  end

  def allow_correction_on_end? = false

  def start_shift
    result = ShiftManage.sign_in(person: shift_person,
                                 position_id: params[:position_id],
                                 slot_id: params[:slot_id].presence,
                                 force: params[:force_sign_in].present?,
                                 reason: params[:signin_force_reason].presence,
                                 user: current_user)

    callsign = shift_person.callsign
    case result.status
    when :success
      @shift_transition = :started
      redirect_to shift_return_path, success: "#{callsign} is on shift. Happy dusty adventures."
    when :blocked
      render_shift_modal "blocked_modal",
                         blockers: result.blockers,
                         title: "Check In Is Blocked",
                         action_noun: "shift check-in",
                         form_url: shift_start_path,
                         form_method: :post,
                         form_params: { position_id: params[:position_id],
                                        slot_id: params[:slot_id].presence }.compact
    when :already_on_duty
      redirect_to shift_return_path, error: "#{callsign} is already on duty."
    when :position_not_held
      redirect_to shift_return_path,
                  error: "#{callsign} does not hold that position and cannot start the shift."
    else
      redirect_shift_failure(result.status, "check-in")
    end
  end

  def end_shift
    entry = locate_on_duty_entry
    return unless entry

    if entry.too_short? && params[:confirmed].blank?
      return render_shift_modal "too_short_modal", entry: entry
    end

    result = ShiftManage.sign_off(entry, user: current_user)
    if result.status == :already_signed_off
      return redirect_to shift_return_path, error: "#{shift_person.callsign} was already signed off."
    end

    # The Inactive-to-Active conversion rides the flash as a flag, not as toast
    # text: a toast dismisses itself, and this has to be seen. The next page
    # pulls it out in load_shift_manage_state and opens converted_modal.
    flash[:status_converted] = true if result.now_active
    @shift_transition = :ended
    redirect_to shift_return_path, success: "#{shift_person.callsign} signed off. Enjoy your rest."
  end

  # Resume a shift that was ended by mistake.
  def resignin
    entry = Timesheet.includes(:position).find_by(id: params[:entry_id],
                                                  person_id: shift_person.id)
    unless entry
      return redirect_to shift_return_path, error: "Timesheet entry not found."
    end

    result = ShiftManage.resignin(entry)
    case result.status
    when :success
      redirect_to shift_return_path,
                  success: "#{shift_person.callsign} is back on shift with #{entry.position.title}."
    when :already_on_duty
      redirect_to shift_return_path, error: "#{shift_person.callsign} is already on duty."
    else
      redirect_shift_failure(result.status, "shift resume")
    end
  end

  # Renders the correct-position modal into the page's modal frame.
  def correct_position
    entry = locate_on_duty_entry
    return unless entry

    render_shift_modal "correct_position_modal", entry: entry, positions: shift_positions
  end

  def update_position
    entry = locate_on_duty_entry
    return unless entry

    result = ShiftManage.update_position(entry,
                                         position_id: params[:position_id],
                                         force: params[:force_sign_in].present?,
                                         reason: params[:signin_force_reason].presence,
                                         user: current_user)
    case result.status
    when :success
      redirect_to shift_return_path, success: "Position updated."
    when :blocked
      render_shift_modal "blocked_modal",
                         blockers: result.blockers,
                         title: "Position Update Is Blocked",
                         action_noun: "position update",
                         form_url: shift_correct_position_path,
                         form_method: :patch,
                         form_params: { position_id: params[:position_id], entry_id: entry.id }
    when :position_not_held
      redirect_to shift_return_path,
                  error: "#{shift_person.callsign} does not hold that position. " \
                         "The timesheet entry cannot be updated."
    else
      redirect_shift_failure(result.status, "position update")
    end
  end

  def delete_mistake
    entry = locate_on_duty_entry
    return unless entry

    result = ShiftManage.delete_mistake(entry)
    if result.status == :success
      redirect_to shift_return_path, success: "Accidental timesheet entry deleted."
    else
      redirect_shift_failure(result.status, "entry deletion")
    end
  end

  private

  # Data the check-in/out panel needs; host page actions call this.
  # shift_positions is NOT loaded here — the eligibility pass behind it is
  # per-position query work the on-duty state never uses; views pull it
  # lazily through the memoized helper.
  def load_shift_manage_state
    @on_duty_entry = Timesheet.find_person_on_duty(shift_person.id)
    @shift_training_passed = ShiftManage.training_passed?(shift_person)
    # Read, then delete: the layout toasts every flash entry it still finds.
    # Never test delete's return -- FlashHash#delete returns the flash itself,
    # which is present whenever the redirect also carried a toast.
    @status_converted = flash[:status_converted].present?
    flash.delete(:status_converted)
    return if @on_duty_entry

    @upcoming_slots = Scheduling::Query.retrieve_starting_slots_for_person(shift_person.id)
    @recent_entry = ShiftManage.recently_signed_off_entry(shift_person)
  end

  def shift_positions
    @shift_positions ||= ShiftManage.position_options(
      shift_person,
      self_serve: shift_self_serve?,
      promote_self: shift_self_serve? && has_role?(Role::SHIFT_MANAGEMENT_SELF)
    )
  end

  def shift_can_force?
    ShiftManage.can_force?(current_user)
  end

  # The end/correct/delete actions operate on the person's current on-duty
  # entry; a stale entry_id means the state changed since the page rendered.
  def locate_on_duty_entry
    entry = Timesheet.find_person_on_duty(shift_person.id)

    if entry.nil?
      redirect_to shift_return_path, error: "#{shift_person.callsign} is not on duty."
      return nil
    end

    if params[:entry_id].present? && params[:entry_id].to_i != entry.id
      redirect_to shift_return_path,
                  error: "The shift status changed since the page was loaded. " \
                         "Review the current status and try again."
      return nil
    end

    entry
  end

  def redirect_shift_failure(status, action_phrase)
    message =
      case status
      when :position_not_eligible
        "That position is not eligible for timesheet entries."
      when :force_not_allowed
        "You do not have the privileges to force the #{action_phrase}."
      when :missing_force_reason
        "A reason must be given to force the #{action_phrase}."
      when :not_on_duty
        "#{shift_person.callsign} is not on duty."
      when :not_signed_off
        "The shift has not ended — there is nothing to resume."
      # No page reachable from here passes a start_time today, but sign_in is
      # the shared command and its status vocabulary grew when Rollcall added
      # one. A shared dispatcher that cannot name every status its command can
      # return is a bug waiting for the second caller.
      when :invalid_start_time, :start_time_out_of_range
        "The check-in time must be a real time within the last several hours."
      when :start_time_overlaps
        "That check-in time falls inside a shift #{shift_person.callsign} has already finished."
      else
        "The #{action_phrase} failed with an unexpected status [#{status}]. " \
          "This is a bug — please report it to the Tech Ninjas."
      end
    redirect_to shift_return_path, error: message
  end

  # update (not append) so chained interstitials — too-short into
  # correct-position, blocked after a force retry — replace one another
  # instead of stacking open dialogs.
  def render_shift_modal(partial, locals = {})
    render turbo_stream: turbo_stream.update("modal", partial: "common/shift_manage/#{partial}",
                                                      locals: locals)
  end
end
