# frozen_string_literal: true

require "test_helper"

# The Cruise Direction page's data layer: which shift the page opens on, what a
# pod card knows about its members, and who the add dialog is allowed to offer.
class CruiseDirectionBoardTest < ActiveSupport::TestCase
  include TrainingSlotTestHelper
  include PersonTestFactory
  include ActiveSupport::Testing::TimeHelpers

  YEAR = 2025

  setup do
    # Noon on the second day of the event, an hour into the shift below.
    travel_to Time.zone.local(YEAR, 8, 26, 12, 0, 0)
    Current.reset

    @dirt = position(Position::DIRT, "Dirt")
    @green_dot = position(Position::DIRT_GREEN_DOT, "Dirt - Green Dot")
    # Not a Cruise Direction position: someone signed in here is on duty but
    # has no business on this board.
    @mentor_position = position(Position::MENTOR, "Mentor", cruise_direction: false)

    @slot = create_slot(@dirt, begins: Time.zone.local(YEAR, 8, 26, 11, 0, 0),
                        ends: Time.zone.local(YEAR, 8, 26, 17, 0, 0), description: "Dirt shift")
  end

  teardown do
    Current.reset
    travel_back
  end

  # --- the shift picker ---

  test "the page opens on the shift that is running now" do
    earlier = dirt_time_slot(begins: Time.zone.local(YEAR, 8, 26, 5, 0, 0))
    running = dirt_time_slot(begins: Time.zone.local(YEAR, 8, 26, 11, 0, 0))
    later = dirt_time_slot(begins: Time.zone.local(YEAR, 8, 26, 17, 0, 0))

    suggested = CruiseDirectionBoard.suggested_shift([earlier, running, later])

    assert_equal running.id, suggested.id
  end

  test "no shift is suggested when nothing is running" do
    upcoming = dirt_time_slot(begins: Time.zone.local(YEAR, 8, 27, 11, 0, 0))

    assert_nil CruiseDirectionBoard.suggested_shift([upcoming])
  end

  # --- the board ---

  test "the board lists a shift's pods in order with their members" do
    first = Pod.create_shift_pod!(@slot, location: "Esplanade & 3:00")
    second = Pod.create_shift_pod!(@slot, transport: Pod::TRANSPORT_BICYCLE)
    firecracker = signed_in("Firecracker", @dirt, at: @slot.begins)
    dusty = signed_in("DustyBoots", @green_dot, at: @slot.begins + 5.minutes)
    first.add_person!(firecracker)
    second.add_person!(dusty)

    board = CruiseDirectionBoard.for_slot(@slot)

    assert_equal [1, 2], board.cards.map { |card| card.pod.sort_index }
    assert_equal 2, board.pod_count
    assert_equal 2, board.member_count
    assert_equal "Esplanade & 3:00", board.cards.first.location
    assert_equal Pod::TRANSPORT_BICYCLE, board.cards.second.transport

    member = board.cards.first.members.sole

    assert_equal "Firecracker", member.person.callsign
    assert_predicate member, :on_duty?
    assert_equal "Dirt", member.position_title
    assert_equal @slot.begins, member.on_duty_at
  end

  # Signing out does not take someone out of the pod -- only a removal does.
  # The card says "not checked in" instead, which is upstream's rule.
  test "a member whose shift has ended stays in the pod without duty details" do
    pod = Pod.create_shift_pod!(@slot)
    person = signed_in("Firecracker", @dirt, at: @slot.begins)
    pod.add_person!(person)
    # Every timesheet save wants a reason, sign-outs included.
    Timesheet.find_person_on_duty(person.id).update!(off_duty: Current.time,
                                                     additional_notes: "shift ended")

    member = CruiseDirectionBoard.for_slot(@slot).cards.sole.members.sole

    assert_equal "Firecracker", member.person.callsign
    assert_not_predicate member, :on_duty?
    assert_nil member.position_title
  end

  test "the board counts people on duty that no one has put in a pod" do
    pod = Pod.create_shift_pod!(@slot)
    podded = signed_in("Firecracker", @dirt, at: @slot.begins)
    signed_in("Hazmat", @green_dot, at: @slot.begins)
    pod.add_person!(podded)

    board = CruiseDirectionBoard.for_slot(@slot)

    assert_equal 1, board.unassigned_count
    assert_equal "Hazmat", board.unassigned.sole.person.callsign
  end

  test "someone on duty outside the Cruise Direction positions is not on the board" do
    signed_in("Mentormost", @mentor_position, at: @slot.begins)

    assert_equal 0, CruiseDirectionBoard.for_slot(@slot).unassigned_count
  end

  # --- the add dialog ---

  test "the add dialog splits candidates at the prior-shift cutoff" do
    now = signed_in("Firecracker", @dirt, at: @slot.begins)
    earlier = signed_in("Riverbed", @dirt, at: @slot.begins - 1.hour)
    just_before = signed_in("Cinder", @dirt, at: @slot.begins - 59.minutes)

    pools = CruiseDirectionBoard.pools_for(@slot)

    assert_equal ["Cinder", "Firecracker"], pools.current.map { |c| c.person.callsign },
                 "checked in within the hour, in callsign order"
    assert_equal ["Riverbed"], pools.prior.map { |c| c.person.callsign },
                 "an hour early or more looks like the shift before this one"
    assert_equal [now.id, earlier.id, just_before.id].to_set,
                 (pools.current + pools.prior).map { |c| c.person.id }.to_set
  end

  # Being in a pod already is a different refusal with a better message, so
  # eligibility is about the shift alone.
  test "eligibility covers everyone on the shift, podded or not" do
    pod = Pod.create_shift_pod!(@slot)
    podded = signed_in("Firecracker", @dirt, at: @slot.begins)
    free = signed_in("Hazmat", @dirt, at: @slot.begins)
    stranger = create_person("Bystander")
    pod.add_person!(podded)

    eligible = CruiseDirectionBoard.eligible_person_ids(@slot)

    assert_includes eligible, podded.id
    assert_includes eligible, free.id
    assert_not_includes eligible, stranger.id
  end

  # The page can look at any shift of any year, so "on duty" has to mean "on
  # duty for THIS shift" -- otherwise tonight's crew is offered as though they
  # were waiting for a pod on a shift that ended days ago.
  test "someone who checked in after the shift ended is not on its board" do
    pod = Pod.create_shift_pod!(@slot)
    member = signed_in("Firecracker", @dirt, at: @slot.begins)
    pod.add_person!(member)
    signed_in("Latecomer", @dirt, at: @slot.ends + 1.hour)

    board = CruiseDirectionBoard.for_slot(@slot)

    assert_equal 0, board.unassigned_count, "they belong to a later shift"
    assert_empty CruiseDirectionBoard.pools_for(@slot).current.map { |c| c.person.callsign } - ["Firecracker"]
  end

  # An entry no one ever closed matches "still on duty" for the rest of the
  # year. Without a lower bound it would sit in "Waiting for a pod" on every
  # later shift -- inflating the one number this page exists to drive to zero,
  # with no control here able to clear it. Closing those is Mass Sign-Out's job.
  test "a shift left open days ago is not waiting for a pod on this one" do
    signed_in("Ghost", @dirt, at: @slot.begins - 3.days)
    signed_in("Hazmat", @dirt, at: @slot.begins)

    board = CruiseDirectionBoard.for_slot(@slot)

    assert_equal ["Hazmat"], board.unassigned.map { |row| row.person.callsign }
    assert_equal ["Hazmat"], CruiseDirectionBoard.pools_for(@slot).current.map { |c| c.person.callsign }
    assert_empty CruiseDirectionBoard.pools_for(@slot).prior
    assert_not_includes CruiseDirectionBoard.eligible_person_ids(@slot),
                        Person.find_by(callsign: "Ghost").id
  end

  # Still out on the shift before this one is ordinary -- that is what the
  # dialog's folded list is for -- so the lower bound has to leave room for it.
  test "someone still out from the shift before is offered, folded away" do
    signed_in("Riverbed", @dirt, at: @slot.begins - 5.hours)

    pools = CruiseDirectionBoard.pools_for(@slot)

    assert_empty pools.current
    assert_equal ["Riverbed"], pools.prior.map { |c| c.person.callsign }
  end

  test "someone holding two open entries is reported by the later one" do
    person = create_person("Doubled")
    Timesheet.create!(person_id: person.id, position_id: @dirt.id,
                      on_duty: @slot.begins - 5.hours, additional_notes: "the shift before")
    Timesheet.create!(person_id: person.id, position_id: @green_dot.id,
                      on_duty: @slot.begins, additional_notes: "this shift")

    candidate = CruiseDirectionBoard.for_slot(@slot).unassigned.sole

    assert_equal "Doubled", candidate.person.callsign, "listed once, not twice"
    assert_equal "Dirt - Green Dot", candidate.position_title
    assert_equal @slot.begins, candidate.on_duty_at
  end

  test "a member's duty details come from the shift they were podded on" do
    pod = Pod.create_shift_pod!(@slot)
    person = create_person("Firecracker")
    # Their shift for this slot, closed out; then a new one tonight.
    Timesheet.create!(person_id: person.id, position_id: @dirt.id, on_duty: @slot.begins,
                      off_duty: @slot.ends, additional_notes: "the shift itself")
    Timesheet.create!(person_id: person.id, position_id: @green_dot.id,
                      on_duty: @slot.ends + 6.hours, additional_notes: "a later shift")
    pod.add_person!(person)

    member = CruiseDirectionBoard.for_slot(@slot).cards.sole.members.sole

    assert_not_predicate member, :on_duty?, "tonight's shift is not this pod's"
    assert_nil member.position_title
  end

  test "the add dialog never offers someone who is already in a pod" do
    pod = Pod.create_shift_pod!(@slot)
    person = signed_in("Firecracker", @dirt, at: @slot.begins)
    signed_in("Hazmat", @dirt, at: @slot.begins)
    pod.add_person!(person)

    pools = CruiseDirectionBoard.pools_for(@slot)

    assert_equal ["Hazmat"], pools.current.map { |c| c.person.callsign }
  end

  test "someone taken out of a pod can be added again" do
    pod = Pod.create_shift_pod!(@slot)
    person = signed_in("Firecracker", @dirt, at: @slot.begins)
    pod.add_person!(person)
    pod.remove_person!(person)

    assert_equal ["Firecracker"], CruiseDirectionBoard.pools_for(@slot).current.map { |c| c.person.callsign }
  end

  test "the selectable positions are the ones flagged for Cruise Direction" do
    titles = CruiseDirectionBoard.positions.map(&:title)

    assert_includes titles, "Dirt"
    assert_includes titles, "Dirt - Green Dot"
    assert_not_includes titles, "Mentor"
  end

  private

  def position(id, title, cruise_direction: true)
    Position.find_by(id:) ||
      Position.create!(id:, title:, type: Position::TYPE_FRONTLINE, active: true, cruise_direction:)
  end

  def dirt_time_slot(begins:)
    create_slot(@dirt, begins:, ends: begins + 6.hours, description: "Dirt shift")
    Slot.retrieve_dirt_times(YEAR).find { |shift| shift.begins == begins }
  end

  def signed_in(callsign, position, at:)
    person = create_person(callsign)
    Timesheet.create!(person_id: person.id, position_id: position.id, on_duty: at,
                      additional_notes: "signed in for the shift")
    person
  end
end
