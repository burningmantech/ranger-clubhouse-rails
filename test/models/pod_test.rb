# frozen_string_literal: true

require "test_helper"

# The pod bookkeeping every route depends on: trios that stay linked, counts
# that stay honest, and numbering that stays 1..N.
class PodTest < ActiveSupport::TestCase
  include TrainingSlotTestHelper
  include PersonTestFactory
  include ActiveSupport::Testing::TimeHelpers

  YEAR = 2025

  setup do
    travel_to Time.zone.local(YEAR, 8, 25, 12, 0, 0)
    Current.reset

    @position = Position.create!(id: Position::ALPHA, title: "Alpha",
                                 type: Position::TYPE_FRONTLINE, active: true)
    @slot = create_slot(@position, begins: Time.zone.local(YEAR, 8, 26, 7, 0, 0),
                        ends: Time.zone.local(YEAR, 8, 26, 13, 0, 0), description: "Alpha walk")
    @alpha = create_person("PodAlphaOne", status: Person::ALPHA)
    @other_alpha = create_person("PodAlphaTwo", status: Person::ALPHA)
    @mentor = create_person("PodMentorOne")
  end

  teardown do
    Current.reset
    travel_back
  end

  # --- the trio ---

  test "creating a pod writes a linked mentor, alpha, and mitten row" do
    mentor_pod = Pod.create_alpha_set!(@slot)

    assert_equal Pod::TYPE_MENTOR, mentor_pod.type
    assert_equal 1, mentor_pod.sort_index
    assert_nil mentor_pod.mentor_pod_id

    types = mentor_pod.sub_pods.map(&:type).sort
    assert_equal [Pod::TYPE_ALPHA, Pod::TYPE_MITTEN], types
    assert(mentor_pod.sub_pods.all? { |pod| pod.sort_index == 1 })
    assert(mentor_pod.sub_pods.all? { |pod| pod.slot_id == @slot.id })
    assert_not_nil mentor_pod.formed_at
  end

  test "each new pod goes on the end of the walk order" do
    first = Pod.create_alpha_set!(@slot)
    second = Pod.create_alpha_set!(@slot)
    third = Pod.create_alpha_set!(@slot)

    assert_equal [1, 2, 3], [first, second, third].map(&:sort_index)
  end

  test "deleting a pod takes its trio and memberships with it and closes the gap" do
    first = Pod.create_alpha_set!(@slot)
    second = Pod.create_alpha_set!(@slot)
    third = Pod.create_alpha_set!(@slot)
    alpha_pod = second.sub_pods.find(&:alpha?)
    alpha_pod.add_person!(@alpha)

    second.destroy_set!

    assert_nil Pod.find_by(id: second.id)
    assert_equal 0, Pod.where(mentor_pod_id: second.id).count
    assert_equal 0, PersonPod.where(pod_id: alpha_pod.id).count, "memberships are deleted with the pod"
    assert_equal [1, 2], [first.reload.sort_index, third.reload.sort_index]
  end

  test "pods step through the walk order and stop at the ends" do
    first = Pod.create_alpha_set!(@slot)
    second = Pod.create_alpha_set!(@slot)

    assert second.move!(Pod::MOVE_EARLIER)
    assert_equal [2, 1], [first.reload.sort_index, second.reload.sort_index]

    assert_not second.move!(Pod::MOVE_EARLIER), "already first"
    assert_equal 1, second.reload.sort_index
  end

  # --- membership ---

  test "adding someone stamps the membership and the count" do
    pod = Pod.create_alpha_set!(@slot).sub_pods.find(&:alpha?)

    pod.add_person!(@alpha)

    membership = pod.current_members.first
    assert_equal @alpha.id, membership.person_id
    assert_equal 1, membership.sort_index
    assert_not_nil membership.joined_at
    assert_nil membership.removed_at
    assert_equal 1, pod.reload.person_count
  end

  test "alphas append to the end of their pod while mentors go in at the front" do
    set = Pod.create_alpha_set!(@slot)
    alpha_pod = set.sub_pods.find(&:alpha?)

    alpha_pod.add_person!(@alpha)
    alpha_pod.add_person!(@other_alpha)
    assert_equal [1, 2], alpha_pod.current_members.ordered.map(&:sort_index)

    set.add_person!(@mentor)
    assert_equal [1], set.current_members.map(&:sort_index)
  end

  test "the same person cannot be added to a pod twice" do
    pod = Pod.create_alpha_set!(@slot).sub_pods.find(&:alpha?)
    pod.add_person!(@alpha)

    assert_raises(Pod::MembershipError) { pod.add_person!(@alpha) }
  end

  test "someone already in one pod of a shift cannot be added to another of the same kind" do
    first = Pod.create_alpha_set!(@slot).sub_pods.find(&:alpha?)
    second = Pod.create_alpha_set!(@slot).sub_pods.find(&:alpha?)
    first.add_person!(@alpha)

    error = assert_raises(Pod::MembershipError) { second.add_person!(@alpha) }
    assert_match(/already in Pod 1/, error.message)
  end

  test "being in the alpha pod does not block the mentor pod of the same trio" do
    set = Pod.create_alpha_set!(@slot)
    set.sub_pods.find(&:alpha?).add_person!(@alpha)

    assert_nothing_raised { set.add_person!(@alpha) }
  end

  test "removing someone keeps the row, renumbers the rest, and disbands an emptied pod" do
    pod = Pod.create_alpha_set!(@slot).sub_pods.find(&:alpha?)
    pod.add_person!(@alpha)
    pod.add_person!(@other_alpha)

    pod.remove_person!(@alpha)

    removed = PersonPod.find_by(pod_id: pod.id, person_id: @alpha.id)
    assert_not_nil removed.removed_at, "the row is kept as history"
    assert_equal [@other_alpha.id], pod.current_members.map(&:person_id)
    assert_equal 1, pod.current_members.first.sort_index, "the survivor closes the gap"
    assert_equal 1, pod.reload.person_count

    pod.remove_person!(@other_alpha)
    assert_not_nil pod.reload.disbanded_at
    assert_equal 0, pod.person_count
  end

  test "adding to a disbanded pod reforms it" do
    pod = Pod.create_alpha_set!(@slot).sub_pods.find(&:alpha?)
    pod.add_person!(@alpha)
    pod.remove_person!(@alpha)
    assert_not_nil pod.reload.disbanded_at

    pod.add_person!(@other_alpha)

    assert_nil pod.reload.disbanded_at
  end

  test "relocating moves the membership and leaves the old one as history" do
    first = Pod.create_alpha_set!(@slot).sub_pods.find(&:alpha?)
    second = Pod.create_alpha_set!(@slot).sub_pods.find(&:alpha?)
    first.add_person!(@alpha)

    first.relocate_person!(@alpha, second)

    assert_equal 0, first.current_members.count
    assert_equal [@alpha.id], second.current_members.map(&:person_id)
    assert_not_nil PersonPod.find_by(pod_id: first.id, person_id: @alpha.id).removed_at
    assert_equal 0, first.reload.person_count
    assert_equal 1, second.reload.person_count
  end

  test "the lead flag is only kept on mentor pods" do
    set = Pod.create_alpha_set!(@slot)
    alpha_pod = set.sub_pods.find(&:alpha?)

    set.add_person!(@mentor, is_lead: true)
    alpha_pod.add_person!(@alpha, is_lead: true)

    assert set.current_members.first.is_lead
    assert_not alpha_pod.current_members.first.is_lead, "an alpha pod has no lead"
  end

  test "members step up and down inside their pod" do
    pod = Pod.create_alpha_set!(@slot).sub_pods.find(&:alpha?)
    pod.add_person!(@alpha)
    pod.add_person!(@other_alpha)

    assert pod.move_person!(@other_alpha, Pod::MOVE_UP)
    assert_equal [@other_alpha.id, @alpha.id], pod.current_members.ordered.map(&:person_id)

    assert_not pod.move_person!(@other_alpha, Pod::MOVE_UP), "already first"
  end

  # --- the timesheet hook ---

  test "a member's shift ending stamps left_at without emptying the pod" do
    pod = Pod.create_alpha_set!(@slot).sub_pods.find(&:alpha?)
    timesheet = Timesheet.create!(person_id: @alpha.id, position_id: @position.id,
                                  on_duty: Current.time - 1.hour,
                                  additional_notes: "signed in for the walk")
    pod.add_person!(@alpha)
    assert_equal timesheet.id, pod.current_members.first.timesheet_id,
                 "the open timesheet is captured when they join"

    timesheet.update!(off_duty: Current.time)

    membership = PersonPod.find_by(pod_id: pod.id, person_id: @alpha.id)
    assert_not_nil membership.left_at
    assert_nil membership.removed_at, "going off duty does not take them out of the pod"
    assert_equal 1, pod.reload.person_count
    assert_nil pod.disbanded_at
  end

  # --- auditing ---

  test "membership changes are audited but reordering is not" do
    pod = Pod.create_alpha_set!(@slot).sub_pods.find(&:alpha?)
    pod.add_person!(@alpha)
    pod.add_person!(@other_alpha)

    assert ActionLog.where(event: "person-pod-create").exists?

    before = ActionLog.count
    pod.move_person!(@other_alpha, Pod::MOVE_UP)

    assert_equal before, ActionLog.count, "ordering is not history"
  end

  # --- shift pods (Cruise Direction) ---
  #
  # A shift pod stands alone: no trio, no mentor_pod_id, and a transport and a
  # location of its own.

  test "a shift pod carries its own number, transport, and location" do
    pod = Pod.create_shift_pod!(dirt_slot, transport: Pod::TRANSPORT_BICYCLE, location: "Esplanade & 3:00")

    assert_equal Pod::TYPE_SHIFT, pod.type
    assert_equal 1, pod.sort_index
    assert_equal 1, pod.number, "a pod with no mentor pod is its own number"
    assert_equal Pod::TRANSPORT_BICYCLE, pod.transport
    assert_equal "Esplanade & 3:00", pod.location
    assert_nil pod.mentor_pod_id
  end

  test "a shift pod defaults to travelling on foot and rejects any other transport" do
    pod = Pod.create_shift_pod!(dirt_slot)

    assert_equal Pod::TRANSPORT_FOOT, pod.transport

    pod.transport = "hovercraft"

    assert_not pod.valid?
    assert_includes pod.errors.attribute_names, :transport
  end

  test "a location typed and then cleared reads as no location" do
    pod = Pod.create_shift_pod!(dirt_slot, location: "  Center Camp  ")

    assert_equal "Center Camp", pod.location, "surrounding space is not part of the location"

    pod.update!(location: "   ")

    assert_nil pod.reload.location
  end

  test "each new shift pod goes on the end of the line" do
    slot = dirt_slot
    pods = 3.times.map { Pod.create_shift_pod!(slot) }

    assert_equal [1, 2, 3], pods.map(&:sort_index)
  end

  # What a drag ends in: SortableJS reports the 1-based place the card was let
  # go and the line is rewritten around it.
  test "dropping a pod on a place renumbers the line around it" do
    slot = dirt_slot
    first, second, third = 3.times.map { Pod.create_shift_pod!(slot) }

    assert third.move_to!(1)
    assert_equal [1, 2, 3], [third, first, second].map { |pod| pod.reload.sort_index }
  end

  test "a pod dragged past the end of the line lands on the end" do
    slot = dirt_slot
    first, second, third = 3.times.map { Pod.create_shift_pod!(slot) }

    assert first.move_to!(99)
    assert_equal [1, 2, 3], [second, third, first].map { |pod| pod.reload.sort_index }
  end

  test "dropping a pod back where it started moves nothing" do
    slot = dirt_slot
    pod = Pod.create_shift_pod!(slot)
    Pod.create_shift_pod!(slot)

    assert_not pod.move_to!(1)
    assert_not pod.move_to!(0), "clamped to the first place, which is where it already is"
  end

  test "reordering one shift leaves another shift's pods and the Alpha pods alone" do
    slot = dirt_slot
    other_slot = dirt_slot(begins: Time.zone.local(YEAR, 8, 27, 7, 0, 0))
    mine = 2.times.map { Pod.create_shift_pod!(slot) }
    theirs = 2.times.map { Pod.create_shift_pod!(other_slot) }
    mentor_pod = Pod.create_alpha_set!(@slot)

    assert mine.last.move_to!(1)

    assert_equal [1, 2], theirs.map { |pod| pod.reload.sort_index }
    assert_equal 1, mentor_pod.reload.sort_index
  end

  test "deleting a shift pod takes its memberships and closes the gap" do
    slot = dirt_slot
    first, second, third = 3.times.map { Pod.create_shift_pod!(slot) }
    second.add_person!(@alpha)

    second.destroy_and_renumber!

    assert_not Pod.exists?(second.id)
    assert_empty PersonPod.where(pod_id: second.id)
    assert_equal [1, 2], [first, third].map { |pod| pod.reload.sort_index }
  end

  test "a shift pod's members are listed in callsign order" do
    pod = Pod.create_shift_pod!(dirt_slot)
    zebra = create_person("Zebra")
    apple = create_person("Apple")
    pod.add_person!(zebra)
    pod.add_person!(apple)

    assert_equal ["Apple", "Zebra"], pod.current_members.ordered.map { |row| row.person.callsign }
  end

  test "someone can only be in one pod on a shift" do
    slot = dirt_slot
    first = Pod.create_shift_pod!(slot)
    second = Pod.create_shift_pod!(slot)
    first.add_person!(@alpha)

    error = assert_raises(Pod::MembershipError) { second.add_person!(@alpha) }
    assert_match(/already in Pod 1/, error.message, "the refusal names the pod holding them")
  end

  # The order survives a removal, which is what pins a shift pod's members to
  # callsign: they are all written at sort_index 1 so PersonPod.ordered falls
  # through to the name. Renumbering the survivors 1..N would leave the next
  # person added -- back at 1 -- sorting above every one of them.
  test "a shift pod's members stay in callsign order after someone is taken out" do
    pod = Pod.create_shift_pod!(dirt_slot)
    %w[Apple Bravo Charlie].each { |callsign| pod.add_person!(create_person(callsign)) }
    pod.remove_person!(Person.find_by(callsign: "Apple"))
    pod.add_person!(create_person("Zebra"))

    assert_equal ["Bravo", "Charlie", "Zebra"],
                 pod.current_members.ordered.map { |row| row.person.callsign }
  end

  # --- a location the length rule would refuse ---
  #
  # `pod` is shared with the still-live Laravel page, which has no length rule,
  # so rows longer than this exist. Validating them on every save would make
  # one of them block writes no one asked for -- including, through
  # Pod.shift_ended, that person's sign-out anywhere in the app.

  test "a location too long to write does not block saves that leave it alone" do
    slot = dirt_slot
    legacy = Pod.create_shift_pod!(slot)
    legacy.update_column(:location, "Inner Playa with Mickey - Troubleshooter LEAL")
    after = Pod.create_shift_pod!(slot)
    legacy.reload.add_person!(@alpha)

    assert_equal 1, legacy.reload.person_count, "the counter refresh saved the pod"
    assert after.move_to!(1), "the line renumbers around it"
    assert_nothing_raised { after.reload.destroy_and_renumber! }
    assert_equal 1, legacy.reload.sort_index
  end

  test "a shift ending still stamps a member of a pod whose location is too long" do
    pod = Pod.create_shift_pod!(dirt_slot)
    pod.update_column(:location, "Esplanade & 3:00 to Esplanade & 9:00 sweep")
    entry = Timesheet.create!(person_id: @alpha.id, position_id: Position::DIRT,
                              on_duty: Current.time - 1.hour, additional_notes: "signed in")
    pod.reload.add_person!(@alpha)

    entry.update!(off_duty: Current.time, additional_notes: "signed out")

    assert_not_nil entry.reload.off_duty, "the sign-out persisted"
    assert_not_nil pod.person_pod.find_by(person_id: @alpha.id).left_at
  end

  test "a location being written past the limit is still refused, and says so" do
    pod = Pod.create_shift_pod!(dirt_slot)

    error = assert_raises(ActiveRecord::RecordInvalid) { pod.update!(location: "x" * 35) }

    assert_match(/A pod location cannot be longer than 34 characters/, error.message,
                 "errors.format is bare, so the message names its own subject")
  end

  # --- what a pod is called ---

  test "an orphaned alpha pod has no number rather than claiming Pod 1" do
    mentor_pod = Pod.create_alpha_set!(@slot)
    orphan = mentor_pod.sub_pods.find(&:alpha?)
    orphan.update_column(:mentor_pod_id, nil)

    assert_equal 1, mentor_pod.number
    assert_nil orphan.reload.number, "it has no mentor pod to be named after"
  end

  test "a move needs a place in the line, not just any parameter" do
    slot = dirt_slot
    first = Pod.create_shift_pod!(slot)
    last = Pod.create_shift_pod!(slot)

    assert_not last.move_to!(nil), "a request that lost its position moves nothing"
    assert_not last.move_to!("junk")
    assert_equal [1, 2], [first.reload.sort_index, last.reload.sort_index]
    assert last.move_to!("1"), "a place still moves it"
  end

  private

  def dirt_slot(begins: Time.zone.local(YEAR, 8, 26, 12, 0, 0))
    position = Position.find_by(id: Position::DIRT) ||
               Position.create!(id: Position::DIRT, title: "Dirt",
                                type: Position::TYPE_FRONTLINE, active: true)
    create_slot(position, begins:, ends: begins + 6.hours, description: "Dirt shift")
  end
end
