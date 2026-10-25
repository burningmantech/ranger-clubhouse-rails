# frozen_string_literal: true

require "test_helper"

# Training::TrainerAttendanceReport: the trainer-slot-to-session pairing, the
# status defaults, and the per-trainer grouping and ordering.
class Training::TrainerAttendanceReportTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers
  include TrainingSlotTestHelper

  YEAR = 2026

  setup do
    travel_to Time.zone.local(YEAR, 8, 10, 12, 0, 0)
    Current.reset

    @training = Position.create!(id: Position::GREEN_DOT_TRAINING, title: "Green Dot Training",
                                 type: Position::TYPE_TRAINING, active: true)
    @trainer_position = Position.create!(id: Position::GREEN_DOT_TRAINER, title: "Green Dot Trainer",
                                         type: Position::TYPE_TRAINING, active: true)
  end

  teardown do
    Current.reset
    travel_back
  end

  test "a teaching sign-up reports its session, position title, and status" do
    session = create_slot(@training, begins: Time.zone.local(YEAR, 6, 1, 9, 0, 0), description: "Bright Eyes")
    trainer_slot = create_slot(@trainer_position, begins: Time.zone.local(YEAR, 6, 1, 8, 30, 0),
                               description: "Bright Eyes")
    trainer = sign_up(person(:active_ranger), trainer_slot)
    record_status(trainer, trainer_slot, TrainerStatus::STATUS_ATTENDED)

    report = Training::TrainerAttendanceReport.execute(@training, YEAR)

    assert_equal [trainer.callsign], report.trainers.map(&:callsign)
    row = report.trainers.first.rows.sole
    assert_equal trainer_slot.id, row.slot.id
    assert_equal session.id, row.session_slot_id
    assert_equal "Green Dot Trainer", row.position_title
    assert_equal TrainerStatus::STATUS_ATTENDED, row.status
    assert_equal 1, report.signup_count
    assert_equal 1, report.attended_count
  end

  test "a trainer with no status record is pending" do
    create_slot(@training, begins: Time.zone.local(YEAR, 6, 1, 9, 0, 0))
    trainer_slot = create_slot(@trainer_position, begins: Time.zone.local(YEAR, 6, 1, 8, 30, 0))
    sign_up(person(:active_ranger), trainer_slot)

    report = Training::TrainerAttendanceReport.execute(@training, YEAR)

    assert_equal TrainerStatus::STATUS_PENDING, report.trainers.first.rows.sole.status
    assert_equal 0, report.attended_count
  end

  # The status lives on trainer_slot_id -- a row keyed to the SESSION slot (as
  # the is_lead flag is) must not be read as attendance.
  test "a no-show counts as a sign-up but not as attended" do
    session = create_slot(@training, begins: Time.zone.local(YEAR, 6, 1, 9, 0, 0))
    trainer_slot = create_slot(@trainer_position, begins: Time.zone.local(YEAR, 6, 1, 8, 30, 0))
    trainer = sign_up(person(:active_ranger), trainer_slot)
    record_status(trainer, trainer_slot, TrainerStatus::STATUS_NO_SHOW, slot: session)

    report = Training::TrainerAttendanceReport.execute(@training, YEAR)

    assert_equal TrainerStatus::STATUS_NO_SHOW, report.trainers.first.rows.sole.status
    assert_equal 1, report.signup_count
    assert_equal 0, report.attended_count
  end

  test "a trainer slot that pairs to no session is dropped" do
    create_slot(@training, begins: Time.zone.local(YEAR, 6, 1, 9, 0, 0), description: "Bright Eyes")

    # Right time, wrong description.
    wrong_description = create_slot(@trainer_position, begins: Time.zone.local(YEAR, 6, 1, 8, 30, 0),
                                    description: "Wrong Eyes")
    sign_up(person(:echelon_ranger), wrong_description)

    # Right description, outside the [session.begins - 1 hour, session.ends] window.
    too_early = create_slot(@trainer_position, begins: Time.zone.local(YEAR, 6, 1, 7, 0, 0),
                            description: "Bright Eyes")
    sign_up(person(:retired_ranger), too_early)

    assert_empty Training::TrainerAttendanceReport.execute(@training, YEAR).trainers
  end

  # CapacityReport filters inactive trainer slots; this report deliberately does
  # not -- people still signed up to a cancelled trainer slot are the point.
  test "an inactive trainer slot still reports its sign-ups" do
    create_slot(@training, begins: Time.zone.local(YEAR, 6, 1, 9, 0, 0))
    trainer_slot = create_slot(@trainer_position, begins: Time.zone.local(YEAR, 6, 1, 8, 30, 0),
                               active: false)
    sign_up(person(:active_ranger), trainer_slot)

    assert_equal 1, Training::TrainerAttendanceReport.execute(@training, YEAR).signup_count
  end

  test "trainers are grouped and sorted by callsign, sessions in time order" do
    early = create_slot(@training, begins: Time.zone.local(YEAR, 6, 1, 9, 0, 0), description: "Bright Eyes")
    late = create_slot(@training, begins: Time.zone.local(YEAR, 6, 8, 9, 0, 0), description: "Dim Eyes")
    early_trainers = create_slot(@trainer_position, begins: Time.zone.local(YEAR, 6, 1, 8, 30, 0),
                                 description: "Bright Eyes")
    late_trainers = create_slot(@trainer_position, begins: Time.zone.local(YEAR, 6, 8, 8, 30, 0),
                                description: "Dim Eyes")

    taught_both = person(:active_ranger)
    taught_both.update!(callsign: "zebra")
    sign_up(taught_both, early_trainers)
    sign_up(taught_both, late_trainers)
    record_status(taught_both, early_trainers, TrainerStatus::STATUS_ATTENDED)

    taught_one = person(:retired_ranger)
    taught_one.update!(callsign: "Aardvark")
    sign_up(taught_one, late_trainers)

    report = Training::TrainerAttendanceReport.execute(@training, YEAR)

    assert_equal ["Aardvark", "zebra"], report.trainers.map(&:callsign)
    zebra = report.trainers.second
    assert_equal [early.id, late.id], zebra.rows.map(&:session_slot_id)
    assert_equal 1, zebra.attended_count
    assert_equal 3, report.signup_count
    assert_equal 1, report.attended_count
  end

  test "a training with no trainer positions reports nothing" do
    other = Position.create!(id: Position::IMS_TRAINING, title: "IMS Training",
                             type: Position::TYPE_TRAINING, active: true)
    slot = create_slot(other, begins: Time.zone.local(YEAR, 6, 1, 9, 0, 0))
    sign_up(person(:active_ranger), slot)

    assert_nil Position::TRAINERS[other.id]
    assert_empty Training::TrainerAttendanceReport.execute(other, YEAR).trainers
  end

  test "only the requested year is reported" do
    create_slot(@training, begins: Time.zone.local(YEAR - 1, 6, 1, 9, 0, 0))
    trainer_slot = create_slot(@trainer_position, begins: Time.zone.local(YEAR - 1, 6, 1, 8, 30, 0))
    sign_up(person(:active_ranger), trainer_slot)

    assert_empty Training::TrainerAttendanceReport.execute(@training, YEAR).trainers
    assert_equal 1, Training::TrainerAttendanceReport.execute(@training, YEAR - 1).signup_count
  end

  private

  def sign_up(signee, slot)
    PersonSlot.create!(person_id: signee.id, slot_id: slot.id)
    signee
  end

  def record_status(trainer, trainer_slot, status, slot: trainer_slot)
    TrainerStatus.create!(person_id: trainer.id, slot_id: slot.id,
                          trainer_slot_id: trainer_slot.id, status:)
  end
end
