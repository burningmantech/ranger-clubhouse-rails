# frozen_string_literal: true

require "test_helper"

# ART graduation buckets and the grant. Candidacy requires a passed status --
# the deliberate fix over upstream's any-scoring-record check.
class TrainingSession::GraduationTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers
  include TrainingSlotTestHelper

  YEAR = 2026

  setup do
    travel_to Time.zone.local(YEAR, 8, 10, 12, 0, 0)
    Current.reset
    Current.person = person(:active_ranger)

    @green_dot = Position.create!(id: Position::GREEN_DOT_TRAINING, title: "Green Dot Training",
                                  type: Position::TYPE_TRAINING, active: true)
    @mentee = Position.create!(id: Position::GREEN_DOT_MENTEE, title: "Green Dot Mentee", active: true)
    @sanctuary = Position.create!(id: Position::SANCTUARY_MENTEE, title: "Sanctuary Mentee", active: true)
    @veteran = Position.create!(id: Position::DIRT_GREEN_DOT, title: "Dirt - Green Dot", active: true)
    @dirt_position = Position.create!(id: Position::DIRT, title: "Dirt", active: true)

    @slot = create_slot(@green_dot, begins: Time.zone.local(YEAR, 8, 8, 9, 0, 0))
    @session = TrainingSession.new(@slot, @green_dot)
    @graduation = TrainingSession::Graduation.new(@session)
  end

  teardown do
    Current.reset
    travel_back
  end

  def sign_up(person)
    PersonSlot.create!(person_id: person.id, slot_id: @slot.id)
  end

  def pass(person)
    TraineeStatus.create!(person_id: person.id, slot_id: @slot.id, status: TraineeStatus::STATUS_PASSED)
  end

  # Enough recent dirt volunteering to clear the Green Dot mentee requirements
  # (3 shifts / 18 hours / 1 prior event).
  def meet_requirements(person)
    3.times do |i|
      Timesheet.create!(person_id: person.id, position_id: Position::DIRT,
                        on_duty: Time.zone.local(YEAR - 1, 8, 25 + i, 9, 0, 0),
                        off_duty: Time.zone.local(YEAR - 1, 8, 25 + i, 16, 0, 0),
                        additional_notes: "graduation requirements")
    end
    person.update!(years_as_ranger: [YEAR - 1])
  end

  test "an ART without graduation positions offers nothing" do
    sandman_training = Position.create!(id: Position::SANDMAN_TRAINING, title: "Sandman Training",
                                        type: Position::TYPE_TRAINING, active: true)
    Position.create!(id: Position::SANDMAN, title: "Sandman", active: true)
    slot = create_slot(sandman_training, begins: Time.zone.local(YEAR, 8, 9, 9, 0, 0))
    graduation = TrainingSession::Graduation.new(TrainingSession.new(slot, sandman_training))

    assert graduation.offered?, "Sandman grants positions"

    dirt = Position.create!(id: Position::TRAINING, title: "Training",
                            type: Position::TYPE_TRAINING, active: true)
    dirt_slot = create_slot(dirt, begins: Time.zone.local(YEAR, 8, 9, 9, 0, 0))
    assert_not TrainingSession::Graduation.new(TrainingSession.new(dirt_slot, dirt)).offered?
  end

  test "candidates bucket by auditor, holdings, pass state, and requirements" do
    auditor = person(:auditor_ranger)
    veteran_holder = person(:echelon_ranger)
    already_granted = person(:ranger_with_custom_gender)
    failed = person(:alpha_ranger)
    unscored = person(:past_prospective_ranger)
    incomplete = person(:prospective_ranger)
    ready = person(:active_ranger)

    [auditor, veteran_holder, already_granted, failed, unscored, incomplete, ready].each { |p| sign_up(p) }

    PersonPosition.create!(person_id: veteran_holder.id, position_id: @veteran.id)
    PersonPosition.create!(person_id: already_granted.id, position_id: @mentee.id)
    TraineeStatus.create!(person_id: failed.id, slot_id: @slot.id, status: TraineeStatus::STATUS_NOT_PASSED)
    [veteran_holder, already_granted, incomplete, ready].each { |p| pass(p) }
    meet_requirements(ready)

    buckets = @graduation.candidates.group_by(&:eligibility)
                         .transform_values { |list| list.map { |c| c.person.id } }

    assert_equal [auditor.id], buckets[TrainingSession::Graduation::AUDITOR]
    assert_equal [veteran_holder.id], buckets[TrainingSession::Graduation::FULLY_GRADUATED]
    assert_equal [already_granted.id], buckets[TrainingSession::Graduation::GRADUATED]
    assert_equal [failed.id, unscored.id].sort,
                 buckets[TrainingSession::Graduation::NOT_PASSED].sort,
                 "an explicit fail must NOT count as passed (upstream quirk fixed)"
    assert_equal [incomplete.id], buckets[TrainingSession::Graduation::REQUIREMENTS_INCOMPLETE]
    assert_equal [ready.id], buckets[TrainingSession::Graduation::CANDIDATE]
  end

  test "requirement gaps report the shortfall" do
    pnv = person(:prospective_ranger)
    sign_up(pnv)
    pass(pnv)
    # One short shift, no prior events.
    Timesheet.create!(person_id: pnv.id, position_id: Position::DIRT,
                      on_duty: Time.zone.local(YEAR - 1, 8, 25, 9, 0, 0),
                      off_duty: Time.zone.local(YEAR - 1, 8, 25, 11, 0, 0),
                      additional_notes: "short shift")

    candidate = @graduation.candidates.find { |c| c.person.id == pnv.id }

    assert candidate.override?
    gaps = candidate.gaps
    assert_equal 1, gaps.shifts
    assert_equal 3, gaps.req_shifts
    assert_in_delta 2.0, gaps.hours, 0.01
    assert_equal 0, gaps.events
    assert_equal 3, gaps.messages.size
  end

  test "graduate! grants the positions to selectable candidates only" do
    ready = person(:active_ranger)
    override = person(:prospective_ranger)
    auditor = person(:auditor_ranger)
    [ready, override, auditor].each { |p| sign_up(p) }
    [ready, override].each { |p| pass(p) }
    meet_requirements(ready)

    results = @graduation.graduate!([ready.id, override.id, auditor.id, 999_999])
                         .index_by(&:person_id)

    assert_equal "success", results[ready.id].status
    assert_equal "success", results[override.id].status, "overrides are force-graduatable"
    assert_equal TrainingSession::Graduation::AUDITOR, results[auditor.id].status
    assert_equal "not-found", results[999_999].status

    granted = PersonPosition.where(person_id: ready.id).pluck(:position_id)
    assert_includes granted, @mentee.id
    assert_includes granted, @sanctuary.id
    assert_empty PersonPosition.where(person_id: auditor.id)
  end
end
