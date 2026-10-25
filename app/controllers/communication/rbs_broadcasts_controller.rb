# frozen_string_literal: true

# Composing and sending one broadcast.
#
# Three steps, each its own page: write it, check who it reaches, send it.
# Nothing is sent until the last step, and the recipients are worked out again
# at that point, so what goes out matches what was reviewed.
class Communication::RbsBroadcastsController < ApplicationController
  layout "communication"

  authorize_role Rbs::MEGAPHONE_ROLES,
                 message: "Admin or a Megaphone role is required to send broadcasts."

  before_action :set_type
  before_action :require_type_allowed
  before_action -> { prevent_if_ghd_server("Sending a broadcast") }
  before_action :set_form
  before_action :set_sandbox_notice

  # Step one: write the broadcast. Also where "Edit message" and the shift
  # picker come back to, which is why it answers a POST as well as a GET --
  # and why a POST is answered at 422: Turbo discards a 200 sent back to a
  # form, so a redraw returned as a fresh page never reaches the reader.
  def new
    render_form(status: request.post? ? :unprocessable_entity : :ok)
  end

  # Step two: who it reaches, and what it says. Writes nothing.
  def review
    return render_form unless @form.valid?

    # Gated exactly as the send is: this page names every recipient, so reaching
    # it for a team someone does not manage would hand over the roster whether
    # or not the send that follows is refused.
    return unless audience_allowed?

    @people = Rbs.retrieve_recipients(@type, @form.criteria)

    if @people.empty?
      @form.errors.add(:base, "No one matches what you chose, so there is no one to send to.")
      return render_form
    end

    # Named beside Send, and left out of every count of who the broadcast reaches.
    @unreached = Rbs.unreachable(@people, send_clubhouse: @form.sends_clubhouse?)

    render :review, status: :unprocessable_entity
  end

  # Step three: send it, and report what was queued for delivery.
  def create
    return render_form unless @form.valid?
    return unless audience_allowed?

    people = Rbs.retrieve_recipients(@type, @form.criteria)

    if people.empty?
      @form.errors.add(:base, "No one matches what you chose, so there is no one to send to.")
      return render_form
    end

    @result = Rbs.transmit(type: @type, sender: current_user, criteria: @form.criteria,
                           message: @form.message_parts, people:)

    render :sent, status: :unprocessable_entity
  end

  private

  def set_type
    @type = params[:type]
    return if Rbs::PAGE_TYPES.include?(@type)

    redirect_to communication_rbs_root_path, error: "That kind of broadcast does not exist."
  end

  def require_type_allowed
    return if Rbs.type_allowed?(@type)

    not_authorized_redirect("You are not authorized to send that kind of broadcast.")
  end

  def set_form
    @form = RbsBroadcastForm.new(@type, form_params)
  end

  # Every page here tells the sender which channels deliver to no one, and
  # where email goes while it is being tested.
  def set_sandbox_notice
    @sandboxes, @email_test_address = RbsSandbox.notice
  end

  def form_params
    scoped_params(RbsBroadcastForm::PARAM_SCOPE,
                  :alert_id, :position_signed_up, :slot_position_id, :slot_id, :position_id,
                  :on_site, :attending, :training, :send_sms, :send_email, :send_clubhouse,
                  :sms_message, :subject, :message, :expires_at,
                  statuses: [], position_ids: [])
  end

  # Drawing the form is the only thing that needs the lists of alerts,
  # positions and shifts, and building them is expensive -- so they are built
  # here rather than before every action.
  def render_form(status: :unprocessable_entity)
    set_form_choices
    render :new, status:
  end

  # What the form offers. The lists a team lead sees hold only their own team's
  # positions and shifts.
  def set_form_choices
    @alerts = Rbs.alerts_for(@type)
    @during_event = Rbs.during_event?
    # Only the kinds that reach a fixed group can be counted before the sender
    # has chosen anything.
    @receivers = Rbs.receiver_estimate(@type)

    @position_groups = Rbs.position_groups if @form.has_position?

    if @form.has_muster_position?
      @in_progress_positions = Rbs.in_progress_positions
      @position_groups = Rbs.position_groups
    end

    return unless @form.has_slot?

    @slot_positions = Rbs.slot_positions
    @slots = @form.slot_position_id.present? ? Rbs.slots_for_position(@form.slot_position_id) : []
  end

  # A team lead may only reach their own teams. True when the sender may go
  # ahead; otherwise the form is redrawn with the reason and false is returned.
  #
  # Every criterion arrives as a form value, so what the page offered is not a
  # guard -- the ids are checked here, on the way in.
  def audience_allowed?
    return true unless Rbs.team_only?
    return true if allowed_positions?

    @form.errors.add(:base, "You may only send to a team you manage.")
    render_form
    false
  end

  # A broadcast reaches a team either by naming its positions or by naming one
  # of its shifts, and both have to be checked.
  def allowed_positions?
    criteria = @form.criteria
    position_ids = Array(criteria[:position_ids]).compact_blank

    if criteria[:slot_id].present?
      slot_position_id = Rbs.position_id_for_slot(criteria[:slot_id])
      return false if slot_position_id.blank?

      position_ids += [slot_position_id]
    end

    return false if position_ids.empty?

    # Already integers, and not IdList.parse: a junk muster position arrives
    # cast to 0, and only that 0 fails this count -- parsed away, [] == [] passes.
    position_ids = position_ids.uniq
    TeamManager.manageable_position_ids(current_user.id, position_ids).size == position_ids.size
  end
end
