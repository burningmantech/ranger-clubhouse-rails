# frozen_string_literal: true

# Pod membership: who is out in which pod on one dirt shift.
#
# Every write goes through a Pod method, because each one is several rows: a
# membership, the pod's count, its disbanded flag, and the renumbering of
# whoever is left.
#
# A move between pods arrives here two ways -- dragged from one card to
# another, or picked from the relocate list in someone's dialog -- and both
# land on `update` with the same parameter. One path, one rule.
class ShiftOperations::CruiseDirection::PeopleController < ShiftOperations::CruiseDirection::BaseController
  before_action :load_pod
  before_action :load_person, only: [:edit, :update, :destroy]

  # The add dialog. A GET, so the candidates are looked up when someone presses
  # Add rather than with every board render.
  def new
    @pools = CruiseDirectionBoard.pools_for(@slot)
  end

  def create
    people = Person.where(id: IdList.parse(params[:person_ids])).to_a
    return render_refusal("Pick at least one callsign to add.") if people.empty?

    # Only people this shift could offer. The dialog cannot show anyone else,
    # so this only ever catches a replayed or hand-made request -- but without
    # it any id in the database joins a pod, including someone who never
    # checked in to a Cruise Direction position.
    eligible = CruiseDirectionBoard.eligible_person_ids(@slot)
    people, ineligible = people.partition { |person| eligible.include?(person.id) }

    added, refused = add_people(people)
    refused += ineligible.map { |person| "#{person.callsign} is not checked in for this shift." }
    return render_refusal(refused.join(" ")) if added.empty?

    message = "#{added.to_sentence} added to #{pod_name(@pod)}."
    render_board([message, *refused].join(" "), refused.empty? ? :success : :warning)
  end

  # The dialog for one Ranger: move them to another pod, or take them out.
  def edit
    return render_refusal("#{@person.callsign} is no longer in this pod.") unless member?

    @pods = Pod.shift_pods_for(@slot).to_a
  end

  def update
    # Guarded like `edit` is. Without it, a dialog left open while another
    # operator took this person out answers a Move-with-no-change by asserting
    # they are still in the pod -- while the board redrawn underneath the toast
    # shows them gone.
    return render_refusal("#{@person.callsign} is no longer in #{pod_name(@pod)}.") unless member?

    new_pod = relocation_target
    return render_board("#{@person.callsign} is already in #{pod_name(@pod)}.", :info) unless new_pod

    @pod.relocate_person!(@person, new_pod)
    render_board("#{@person.callsign} moved to #{pod_name(new_pod)}.")
  rescue Pod::MembershipError => e
    render_refusal(e.message)
  end

  def destroy
    @pod.remove_person!(@person)
    render_board("#{@person.callsign} was taken out of #{pod_name(@pod)}.")
  rescue Pod::MembershipError => e
    render_refusal(e.message)
  end

  private

  # Added one at a time so one refusal -- someone already picked up by another
  # pod, which is the whole point of the check -- does not throw away the rest
  # of the selection. Upstream sends one request per person from the browser
  # and reports only the last answer.
  def add_people(people)
    added = []
    refused = []

    # params order is the checkbox order; callsign order is what the toast
    # should read back.
    people.sort_by { |person| person.callsign.to_s.downcase }.each do |person|
      @pod.add_person!(person)
      added << person.callsign
    rescue Pod::MembershipError => e
      refused << e.message
    end

    [added, refused]
  end

  # nil when the request names the pod they are already in -- staying put is
  # not a relocation, and a drag onto their own card is the usual way that
  # happens.
  def relocation_target
    target_id = params[:new_pod_id].presence
    return if target_id.blank? || target_id.to_i == @pod.id

    target = Pod.shift_pods_for(@slot).find_by(id: target_id)
    raise Pod::MembershipError, "That pod is no longer on this shift." unless target

    target
  end

  def member? = @pod.current_members.exists?(person_id: @person.id)

  def load_person
    @person = Person.find_by(id: params[:person_id])
    return if @person

    render_refusal("Unable to determine who to change.")
  end
end
