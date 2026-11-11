# frozen_string_literal: true

require "test_helper"

class ScheduleLogTest < ActiveSupport::TestCase
  include TrainingSlotTestHelper

  YEAR = 2031

  setup do
    @person = person(:active_ranger)
    @admin = person(:auditor_ranger)
    @position = positions(:ood_position)
  end

  # Noon mid-month, well clear of the year's edges on any machine's clock.
  def log(event, slot_id, month:, by: @person, message: "", year: YEAR, target: @person, **data)
    ActionLog.create!(event: "person-slot-#{event}", message:, person_id: by&.id, target_person_id: target.id,
                      data: { "slot_id" => slot_id }.merge(data.transform_keys(&:to_s)),
                      created_at: Time.zone.local(year, month, 15, 12))
  end

  def shift(day, description: "Playa")
    create_slot(@position, begins: Time.zone.local(YEAR, 8, day, 9), description:)
  end

  test "one entry per shift in shift order, its changes oldest first" do
    late = shift(20)
    early = shift(5)
    log("add", late.id, month: 5)
    log("remove", late.id, month: 6, by: @admin)
    log("add", early.id, month: 7, by: @admin, overcapacity: true)
    sign_up(@person, early)

    first, last = ScheduleLog.retrieve(@person, YEAR)

    assert_equal [early.id, late.id], [first.slot_id, last.slot_id]
    assert first.signed_up
    assert_equal [@admin.id], first.sign_ups.map(&:actor_id)
    assert_equal [:overcapacity], first.sign_ups.first.overrides
    assert_empty first.removals
    assert_equal [true, false], [first.overrides?, last.overrides?]

    assert_not last.signed_up
    assert_equal [true, false], last.changes.map(&:added)
    assert_equal [true, false], last.changes.map(&:by_self)
    assert_equal @admin.callsign, last.removals.first.actor.callsign
  end

  # Ungrouped, the sign-up lands under one entry and the removal under another.
  test "a String slot id joins the shift its Integer twin names" do
    slot = shift(5)
    log("add", slot.id.to_s, month: 5)
    log("remove", slot.id, month: 6)

    entries = ScheduleLog.retrieve(@person, YEAR)

    assert_equal [[slot.id, 2]], entries.map { [it.slot_id, it.changes.size] }
  end

  test "a deleted shift keeps its id and sorts by its first change" do
    slot = shift(5)
    gone_id = shift(25).tap(&:delete).id
    log("add", slot.id, month: 6)
    log("add", gone_id, month: 3)

    gone, kept = ScheduleLog.retrieve(@person, YEAR)

    assert_equal gone_id, gone.slot_id
    assert_predicate gone, :deleted?
    assert_not gone.signed_up
    assert_equal slot.id, kept.slot_id
  end

  test "overrides come from the row's data, reasons from a removal's message" do
    slot = shift(5)
    log("add", slot.id, month: 4, message: "added (overcapacity,started)", started: true, overcapacity: true)
    log("remove", slot.id, month: 5, forced: true, message: "removed")
    log("remove", slot.id, month: 6, message: "removed Training - Reno, NV 2019-06-13 09:30:00")
    log("remove", slot.id, month: 7, message: "position revoked")
    log("remove", slot.id, month: 8, message: "slot deletion")

    changes = ScheduleLog.retrieve(@person, YEAR).sole.changes

    assert_equal [%i[overcapacity after_start], [:after_start], [], [], []], changes.map(&:overrides)
    assert_equal [nil, nil, nil, "position revoked", "slot deletion"], changes.map(&:reason)
  end

  test "leaves out other years, other people, other events and rows naming no shift" do
    slot = shift(5)
    log("add", slot.id, month: 5)
    log("remove", slot.id, month: 6, year: YEAR - 1)
    log("remove", slot.id, month: 6, target: @admin)
    log("add-fail", slot.id, month: 6)
    ActionLog.create!(event: "person-slot-remove", message: "removed", person_id: @person.id,
                      target_person_id: @person.id, created_at: Time.zone.local(YEAR, 6, 15, 12))

    entries = ScheduleLog.retrieve(@person, YEAR)

    assert_equal [[slot.id, 1]], entries.map { [it.slot_id, it.changes.size] }
  end
end
