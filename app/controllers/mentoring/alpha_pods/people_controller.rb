# frozen_string_literal: true

# Pod membership: who is in which pod of one Alpha shift.
#
# `:pod_id` is always the sub-pod being written to -- the mentor, mitten, or
# alpha row of a trio -- so one set of actions serves all three kinds and the
# dialog only has to know which pod it was opened from.
#
# Every write goes through a Pod method, because each one is several rows:
# a membership, the pod's count, its disbanded flag, and the renumbering of
# whoever is left.
class Mentoring::AlphaPods::PeopleController < Mentoring::AlphaPods::BaseController
  before_action :load_slot
  before_action :load_pod
  before_action :load_person, only: [:edit, :update, :destroy]

  # The add dialog. A GET so the pools are loaded when someone presses Add
  # rather than with every page view.
  def new
    @pools = AlphaPodBoard.pools_for(@pod, @slot)
  end

  def create
    people = Person.where(id: IdList.parse(params[:person_ids])).index_by(&:id)
    return render_refusal("Pick at least one callsign to add.") if people.empty?

    added, refused = add_people(people)
    return render_refusal(refused.join(" ")) if added.empty?

    message = "#{added.to_sentence} added to Pod #{@pod.number}."
    render_board([message, *refused].join(" "), refused.empty? ? :success : :warning)
  end

  # The update / relocate / remove dialog for one member. The relocation list
  # is every pod of the same kind, in walk order -- an Alpha moves to another
  # alpha pod, never into the mentors.
  def edit
    @member = @pod.current_members.find_by(person_id: @person.id)
    return render_refusal("#{@person.callsign} is no longer in this pod.") unless @member

    @member_pods = Pod.for_slot(@slot).of_type(@pod.type).includes(:mentor_pod)
                      .to_a.sort_by { |pod| pod.number.to_i }
  end

  def update
    if (direction = params[:direction].presence)
      move_member(direction)
    elsif (new_pod = relocation_target)
      @pod.relocate_person!(@person, new_pod, is_lead: lead_param)
      render_board("#{@person.callsign} moved to Pod #{new_pod.number}.")
    elsif @pod.mentor?
      update_lead
    elsif params.key?(:is_lead)
      # Only reachable by a forged request: the dialog does not offer the
      # checkbox off a mentor pod.
      render_refusal("Only mentors can be marked as the lead.")
    else
      # Saving an alpha or mitten member without picking a different pod. There
      # is nothing to write, and that is not an error -- the dialog's only
      # other fields are the relocation select and the reorder buttons.
      render_board("No changes were made to #{@person.callsign}.", :info)
    end
  rescue Pod::MembershipError => e
    render_refusal(e.message)
  end

  def destroy
    @pod.remove_person!(@person)
    render_board("#{@person.callsign} was removed from Pod #{@pod.number}.")
  rescue Pod::MembershipError => e
    render_refusal(e.message)
  end

  private

  # Added one at a time so one refusal -- someone already picked up by another
  # pod, which is the whole point of the check -- does not throw away the rest
  # of the selection.
  def add_people(people)
    added = []
    refused = []

    # params order is the checkbox order; callsign order is what the toast
    # should read back.
    people.values.sort_by { |person| person.callsign.to_s.downcase }.each do |person|
      @pod.add_person!(person, is_lead: lead_param)
      added << person.callsign
    rescue Pod::MembershipError => e
      refused << e.message
    end

    [added, refused]
  end

  def move_member(direction)
    unless Pod::MEMBER_MOVE_DIRECTIONS.include?(direction)
      return render_refusal("That is not a direction someone can move.")
    end

    unless @pod.move_person!(@person, direction)
      return render_board("#{@person.callsign} is already #{direction == Pod::MOVE_UP ? "first" : "last"}.", :info)
    end

    render_board("Pod #{@pod.number} reordered.")
  end

  # is_lead is a mentor-pod idea. Upstream stores it on mitten pods too, where
  # a checkbox left over from the last dialog could set it by accident.
  def update_lead
    membership = @pod.current_members.find_by(person_id: @person.id)
    return render_refusal("#{@person.callsign} is not in this pod.") unless membership

    membership.update!(is_lead: lead_param)
    render_board("#{@person.callsign} updated.")
  end

  # nil when the form named this same pod -- staying put is not a relocation.
  def relocation_target
    target_id = params[:new_pod_id].presence
    return if target_id.blank? || target_id.to_i == @pod.id

    target = Pod.for_slot(@slot).of_type(@pod.type).find_by(id: target_id)
    raise Pod::MembershipError, "That pod is no longer on this shift." unless target

    target
  end

  def lead_param = params[:is_lead] == "1"


  def load_pod
    @pod = Pod.for_slot(@slot).where(type: Pod::ALPHA_SET_TYPES).includes(:mentor_pod)
              .find_by(id: params[:pod_id])
    return if @pod

    render_refusal("That pod is no longer on this shift.")
  end

  def load_person
    @person = Person.find_by(id: params[:person_id])
    return if @person

    render_refusal("Unable to determine who to change.")
  end
end
