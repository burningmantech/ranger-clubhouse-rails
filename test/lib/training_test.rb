# frozen_string_literal: true

require "test_helper"

class TrainingTest < ActiveSupport::TestCase
  include TrainingSlotTestHelper

  # Statuses are passed newest-first; the training-time status is the newest
  # change recorded before the training begins, not a later one (e.g. a
  # resignation after the training).
  test "determine_person_status uses the status in effect at training time" do
    begins = Time.zone.local(2024, 6, 1)
    ps = ->(created_at, new_status) { OpenStruct.new(created_at:, new_status:) }

    statuses = [
      ps.call(begins + 1.year, Person::RESIGNED),
      ps.call(begins - 1.year, Person::ACTIVE)
    ]
    assert_equal Person::ACTIVE, Training.send(:determine_person_status, statuses, begins)

    # No record before the training: fall back to the newest
    assert_equal Person::RESIGNED,
                 Training.send(:determine_person_status, [ps.call(begins + 1.day, Person::RESIGNED)], begins)

    assert_equal "unknown", Training.send(:determine_person_status, nil, begins)

    # Vintage maps to active
    assert_equal Person::ACTIVE,
                 Training.send(:determine_person_status, [ps.call(begins - 1.day, Person::VINTAGE)], begins)
  end

  test "slug is in-person for dirt and the stripped title elsewhere" do
    assert_equal "in-person", Training.slug(Position.new(id: Position::TRAINING, title: "Training"))
    assert_equal "green-dot",
                 Training.slug(Position.new(id: Position::GREEN_DOT_TRAINING, title: "Green Dot Training"))
    assert_equal "radio-practice",
                 Training.slug(Position.new(id: Position::TRAINING_RADIO_PRACTICE, title: "Training - Radio Practice"))
    assert_equal "hq-leads-shorts",
                 Training.slug(Position.new(id: Position::HQ_LEADS_SHORTS_TRAINING, title: "HQ Leads & Shorts Training"))
  end

  test "find_training_position resolves slugs and refuses everything else" do
    green_dot = Position.create!(id: Position::GREEN_DOT_TRAINING, title: "Green Dot Training",
                                 type: Position::TYPE_TRAINING, active: true)
    Position.create!(id: Position::GREEN_DOT_TRAINER, title: "Green Dot Trainer",
                     type: Position::TYPE_TRAINING, active: true)

    assert_equal green_dot, Training.find_training_position("green-dot")

    # Trainer positions are also type Training but never resolve.
    assert_raises(Training::NotTrainingPositionError) { Training.find_training_position("green-dot-trainer") }
    # Numeric ids are no longer accepted.
    assert_raises(Training::NotTrainingPositionError) { Training.find_training_position(green_dot.id.to_s) }
    assert_raises(Training::NotTrainingPositionError) { Training.find_training_position("no-such-training") }
  end
  # required_by is the requiring positions the PERSON holds. Holding none of them
  # falls back to the not-yet-granted hint, and a training nothing maps to (the
  # base Training position) gets no entry at all -- never an "Unknown" row.
  test "retrieve_education lists only held requiring positions, with the not-granted fallback" do
    ranger = person(:active_ranger)
    year = 2024
    sandman_training = Position.create!(id: Position::SANDMAN_TRAINING, title: "Sandman Training",
                                        type: Position::TYPE_TRAINING, active: true)
    Position.create!(id: Position::SANDMAN, title: "Sandman", type: Position::TYPE_FRONTLINE, active: true,
                     training_position_id: sandman_training.id)
    Position.create!(title: "Sandman Quad Lead", type: Position::TYPE_FRONTLINE, active: true,
                     training_position_id: sandman_training.id)
    training = Position.create!(id: Position::TRAINING, title: "Training",
                                type: Position::TYPE_TRAINING, active: true)

    assert_equal [{ id: Position::SANDMAN, title: "Sandman", not_granted: true }],
                 Training.retrieve_education(ranger.id, sandman_training, year).required_by

    PersonPosition.create!(person: ranger, position_id: Position::SANDMAN)
    assert_equal [{ id: Position::SANDMAN, title: "Sandman" }],
                 Training.retrieve_education(ranger.id, sandman_training, year).required_by

    assert_empty Training.retrieve_education(ranger.id, training, year).required_by
  end

  # A verdict a trainer entered settles the session at once; only a session no
  # one has scored waits out the grace period. Every status short of a pass
  # also takes the fallback that used to raise.
  test "retrieve_education gives the grace period to an unscored session only" do
    training = Position.create!(id: Position::TRAINING, title: "Training",
                                type: Position::TYPE_TRAINING, active: true)
    ranger = person(:active_ranger)
    session = create_slot(training, begins: Time.zone.local(2026, 5, 2, 9, 0, 0))
    PersonSlot.create!(person_id: ranger.id, slot_id: session.id)
    row = TraineeStatus.create!(person: ranger, slot: session)

    {
      TraineeStatus::STATUS_PASSED => [Training::PASS, Training::PASS],
      TraineeStatus::STATUS_PENDING => [Training::PENDING, Training::FAIL],
      TraineeStatus::STATUS_NO_SHOW => [Training::FAIL, Training::FAIL],
      TraineeStatus::STATUS_NOT_PASSED => [Training::FAIL, Training::FAIL]
    }.each do |status, (within_grace, after_grace)|
      row.update!(status:)

      travel_to(session.ends + 1.hour) do
        assert_equal within_grace, Training.retrieve_education(ranger.id, training, 2026).status,
                     "#{status}, within the grace period"
      end
      travel_to(session.ends + 4.days) do
        assert_equal after_grace, Training.retrieve_education(ranger.id, training, 2026).status,
                     "#{status}, after the grace period"
      end
    end
  end

  # With two sessions it is the later one's own verdict that counts: a retake
  # the trainer already marked leaves nothing to wait for either.
  test "retrieve_education judges a retake by its own verdict" do
    training = Position.create!(id: Position::TRAINING, title: "Training",
                                type: Position::TYPE_TRAINING, active: true)
    ranger = person(:active_ranger)
    first_session = create_slot(training, begins: Time.zone.local(2026, 5, 2, 9, 0, 0))
    retake = create_slot(training, begins: Time.zone.local(2026, 6, 6, 9, 0, 0))
    { first_session => TraineeStatus::STATUS_NOT_PASSED, retake => TraineeStatus::STATUS_NO_SHOW }.each do |session, status|
      PersonSlot.create!(person_id: ranger.id, slot_id: session.id)
      TraineeStatus.create!(person: ranger, slot: session, status:)
    end

    travel_to(retake.ends + 1.hour) do
      education = Training.retrieve_education(ranger.id, training, 2026)
      assert_equal Training::FAIL, education.status
      assert_equal retake.id, education.slot.id
    end
  end

  # Someone signed up only to teach, with no session marked attended, takes the
  # status of the session the fallback picks, as upstream: pending until marked,
  # or a no-show.
  test "retrieve_education gives an unattended trainer the session's own status" do
    training = Position.create!(id: Position::TRAINING, title: "Training",
                                type: Position::TYPE_TRAINING, active: true)
    trainer = Position.create!(id: Position::TRAINER, title: "Trainer",
                               type: Position::TYPE_TRAINING, active: true)
    ranger = person(:active_ranger)
    session = create_slot(training, begins: Time.zone.local(2026, 5, 2, 9, 0, 0))
    teaching = create_slot(trainer, begins: session.begins)
    PersonSlot.create!(person_id: ranger.id, slot_id: teaching.id)

    education = Training.retrieve_education(ranger.id, training, 2026)
    assert_equal Training::PENDING, education.status
    assert_equal teaching.id, education.slot.id
    assert education.is_trainer

    TrainerStatus.create!(person: ranger, slot: session, trainer_slot: teaching,
                          status: TrainerStatus::STATUS_NO_SHOW)
    assert_equal Training::NO_SHOW, Training.retrieve_education(ranger.id, training, 2026).status
  end

  # By team, not by training_position_id: pointing a position at an ART there
  # also makes its holders need that ART's pass to sign in.
  test "an ART mentoring training pairs the mentor and mentee positions flagged on its team" do
    team = teams(:green_dot_cadre)
    training = Position.create!(id: Position::GREEN_DOT_TRAINING, title: "Green Dot Training",
                                type: Position::TYPE_TRAINING, team:, has_art_mentoring: true)
    mentor = Position.create!(title: "Green Dot Mentor", type: Position::TYPE_FRONTLINE, team:, is_art_mentor: true)
    mentee = Position.create!(title: "Green Dot Mentee", type: Position::TYPE_FRONTLINE, team:, is_art_mentee: true)
    # Flagged, but on a team that runs no ART mentoring training.
    Position.create!(title: "Khaki Mentor", type: Position::TYPE_FRONTLINE, team: teams(:khaki_team),
                     is_art_mentor: true)

    assert_equal mentor.id, Training.mentor_position_id(training)
    assert_equal mentee.id, Training.mentee_position_id(training)
    assert_equal [training.id, mentor.id, mentee.id], Training.survey_position_ids(training)
    assert_equal [mentor.id], Training.cadre_position_ids(:mentor)
    assert_equal [mentee.id], Training.cadre_position_ids(:mentee)

    training.update!(has_art_mentoring: false)

    assert_nil Training.mentor_position_id(training)
    assert_nil Training.mentee_position_id(training)
    assert_equal [training.id], Training.survey_position_ids(training)
    assert_empty Training.cadre_position_ids(:mentor)
  end
end
