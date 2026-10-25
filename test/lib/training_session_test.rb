# frozen_string_literal: true

require "test_helper"

# TrainingSession: the trainee/trainer roster assembly (retrieveStudents /
# retrieveTrainers port), the score mutation with its audit trail and role
# cache purge, the trainer bulk save, and the add-person search.
class TrainingSessionTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers
  include TrainingSlotTestHelper

  YEAR = 2026

  setup do
    travel_to Time.zone.local(YEAR, 8, 10, 12, 0, 0)
    Current.reset
    Current.person = person(:active_ranger)

    @dirt = Position.create!(id: Position::TRAINING, title: "Training",
                             type: Position::TYPE_TRAINING, active: true)
    @trainer_position = Position.create!(id: Position::TRAINER, title: "Trainer",
                                         type: Position::TYPE_TRAINING, active: true)
    @seasonal_position = Position.create!(id: Position::TRAINER_ASSOCIATE, title: "Trainer Associate",
                                          type: Position::TYPE_TRAINING, active: true)

    @slot = create_slot(@dirt, begins: Time.zone.local(YEAR, 8, 8, 9, 0, 0), description: "Bright Eyes")
  end

  teardown do
    Current.reset
    travel_back
  end

  def dirt_session
    TrainingSession.new(@slot, @dirt)
  end

  def sign_up(person, slot = @slot)
    PersonSlot.create!(person_id: person.id, slot_id: slot.id)
  end

  # --- trainees --------------------------------------------------------------

  test "trainees carry status at session time, flags, notes, and fkas in callsign order" do
    prospective = person(:prospective_ranger)
    retired = person(:retired_ranger)
    active = person(:active_ranger)
    [active, prospective, retired].each { |p| sign_up(p) }

    # Status at the session's end, not today: this person was active back then.
    PersonStatus.create!(person_id: retired.id, old_status: Person::ACTIVE, new_status: Person::RETIRED,
                         created_at: Time.zone.local(YEAR - 2, 1, 1))
    PersonStatus.create!(person_id: prospective.id, old_status: Person::ALPHA, new_status: Person::PROSPECTIVE,
                         created_at: Time.zone.local(YEAR, 1, 1))
    PersonStatus.create!(person_id: active.id, old_status: Person::ALPHA, new_status: Person::ACTIVE,
                         created_at: Time.zone.local(YEAR, 1, 1))

    TraineeStatus.create!(person_id: active.id, slot_id: @slot.id, status: TraineeStatus::STATUS_PASSED, rank: 2)
    TraineeNote.record(person_id: active.id, slot_id: @slot.id, note: "Solid radio protocol.")
    TraineeNote.record(person_id: active.id, slot_id: @slot.id, note: "rank change", is_log: true)
    PersonFka.create!(person_id: retired.id, fka: "Barnstormer", fka_normalized: "barnstormer",
                      fka_soundex: "B625")

    trainees = dirt_session.trainees

    assert_equal [active.id, prospective.id, retired.id].sort_by { |id| Person.find(id).callsign.downcase },
                 trainees.map { |t| t.person.id }

    scored = trainees.find { |t| t.person.id == active.id }
    assert_equal TraineeStatus::STATUS_PASSED, scored.training_status
    assert_equal 2, scored.rank
    assert_equal ["Solid radio protocol."], scored.trainer_notes.map(&:note)
    assert_equal 2, scored.notes.size
    assert_not scored.need_ranking

    pnv = trainees.find { |t| t.person.id == prospective.id }
    assert_equal Person::PROSPECTIVE, pnv.status
    assert pnv.need_ranking, "dirt non-actives need a rank"
    assert pnv.needs_rank?
    assert_equal TraineeStatus::STATUS_PENDING, pnv.training_status

    former = trainees.find { |t| t.person.id == retired.id }
    assert former.is_retired
    assert former.need_ranking
    assert_includes former.fkas, "Barnstormer"
    assert_equal Person::RETIRED, former.status
  end

  test "a legacy rank of 0 reads as unranked" do
    ranger = person(:active_ranger)
    sign_up(ranger)
    status = TraineeStatus.create!(person_id: ranger.id, slot_id: @slot.id, status: TraineeStatus::STATUS_PASSED)
    status.update_column(:rank, 0)

    trainee = dirt_session.trainee(ranger.id)

    assert_nil trainee.rank
    assert_nil trainee.rank_label
  end

  test "a person not signed up has no trainee record" do
    assert_nil dirt_session.trainee(person(:active_ranger).id)
  end

  test "personnel flags surface for the session's year" do
    flagged = person(:auditor_ranger)
    clear = person(:active_ranger)
    [flagged, clear].each { |p| sign_up(p) }
    PersonIntake.create!(person_id: flagged.id, year: YEAR, personnel_rank: Intake::FLAG)

    assert dirt_session.trainee(flagged.id).personnel_issue
    assert_not dirt_session.trainee(clear.id).personnel_issue
  end

  test "ART sessions mark prospectives who have not held a trained position" do
    green_dot = Position.create!(id: Position::GREEN_DOT_TRAINING, title: "Green Dot Training",
                                 type: Position::TYPE_TRAINING, active: true)
    Position.create!(id: Position::DIRT_GREEN_DOT, title: "Dirt - Green Dot",
                     training_position_id: green_dot.id, active: true)
    art_slot = create_slot(green_dot, begins: Time.zone.local(YEAR, 8, 9, 9, 0, 0))
    vet = person(:active_ranger)
    newbie = person(:prospective_ranger)
    [vet, newbie].each { |p| sign_up(p, art_slot) }
    PersonPosition.create!(person_id: vet.id, position_id: Position::DIRT_GREEN_DOT)

    session = TrainingSession.new(art_slot, green_dot)
    trainees = session.trainees.index_by { |t| t.person.id }

    assert_not trainees[vet.id].is_art_prospective
    assert trainees[newbie.id].is_art_prospective
    assert_equal 1, session.vet_count
    assert_equal 1, session.prospective_count
    assert_not trainees[newbie.id].need_ranking, "need_ranking is a dirt-only rule"
  end

  test "the mix counts follow the dirt rules" do
    active = person(:active_ranger)
    prospective = person(:prospective_ranger)
    auditor = person(:auditor_ranger)
    [active, prospective, auditor].each { |p| sign_up(p) }
    active.update!(years_as_ranger: [2023, 2024, 2025])
    PersonStatus.create!(person_id: auditor.id, old_status: Person::AUDITOR, new_status: Person::AUDITOR,
                         created_at: Time.zone.local(YEAR, 1, 1))
    PersonStatus.create!(person_id: prospective.id, old_status: Person::ALPHA, new_status: Person::PROSPECTIVE,
                         created_at: Time.zone.local(YEAR, 1, 1))
    PersonStatus.create!(person_id: active.id, old_status: Person::ALPHA, new_status: Person::ACTIVE,
                         created_at: Time.zone.local(YEAR, 1, 1))

    session = dirt_session

    assert_equal 1, session.vet_count
    assert_equal 1, session.prospective_count
    assert_equal 1, session.auditor_count
    assert_equal 0, session.inactive_retired_count
    assert_equal 0, session.passed_count
    assert_not session.full?
  end

  # --- trainer groups --------------------------------------------------------

  test "trainer groups match exactly-described slots within the window and carry statuses" do
    trainer_slot = create_slot(@trainer_position, begins: Time.zone.local(YEAR, 8, 8, 8, 30, 0),
                               description: "Bright Eyes")
    seasonal_slot = create_slot(@seasonal_position, begins: Time.zone.local(YEAR, 8, 8, 9, 0, 0),
                                description: "Bright Eyes")
    # Wrong description and outside-window slots must not match.
    create_slot(@trainer_position, begins: Time.zone.local(YEAR, 8, 8, 9, 0, 0), description: "Other")
    create_slot(@seasonal_position, begins: Time.zone.local(YEAR, 8, 8, 6, 0, 0), description: "Bright Eyes")

    lead = person(:active_ranger)
    helper = person(:echelon_ranger)
    sign_up(lead, trainer_slot)
    sign_up(helper, seasonal_slot)
    TrainerStatus.create!(person_id: lead.id, slot_id: @slot.id, trainer_slot_id: trainer_slot.id,
                          status: TrainerStatus::STATUS_ATTENDED, is_lead: true)

    session = dirt_session
    groups = session.trainer_groups.index_by(&:position_id)

    assert_equal [Position::TRAINER, Position::TRAINER_ASSOCIATE].sort, groups.keys.sort

    lead_row = groups[Position::TRAINER].trainers.first
    assert_equal TrainerStatus::STATUS_ATTENDED, lead_row.status
    assert lead_row.is_lead

    helper_row = groups[Position::TRAINER_ASSOCIATE].trainers.first
    assert_equal TrainerStatus::STATUS_PENDING, helper_row.status, "no record reads as pending"

    assert_equal 2, session.trainer_count
    assert session.primary_trainers_signed_up?
  end

  test "primary trainer sign-ups are not satisfied by support groups alone" do
    seasonal_slot = create_slot(@seasonal_position, begins: Time.zone.local(YEAR, 8, 8, 9, 0, 0),
                                description: "Bright Eyes")
    sign_up(person(:echelon_ranger), seasonal_slot)

    assert_not dirt_session.primary_trainers_signed_up?
  end

  # --- score! ----------------------------------------------------------------

  def score_form(trainee, **attributes)
    form = Training::ScoreForm.new(**attributes)
    form.trainee = trainee
    form
  end

  # Capture RoleManager.purge_person calls (test cache is a null_store, so
  # interception is the only observable signal).
  def capture_role_purges
    purged = []
    original = RoleManager.method(:purge_person)
    RoleManager.singleton_class.define_method(:purge_person) { |id| purged << id }
    yield
    purged
  ensure
    RoleManager.singleton_class.define_method(:purge_person, original)
  end

  test "score! records the status, audit note, trainer note, and purges the role cache" do
    ranger = person(:active_ranger)
    sign_up(ranger)
    session = dirt_session
    form = score_form(session.trainee(ranger.id), status: TraineeStatus::STATUS_PASSED, rank: 2, note: "Ready for the street.",
                      feedback_delivered: true)
    assert form.valid?

    purged = capture_role_purges do
      session.score!(ranger.id, form)
    end

    status = TraineeStatus.find_by(person_id: ranger.id, slot_id: @slot.id)
    assert_equal TraineeStatus::STATUS_PASSED, status.status
    assert_equal 2, status.rank
    assert status.feedback_delivered
    notes = TraineeNote.where(person_id: ranger.id, slot_id: @slot.id).order(:id)
    assert_equal ["rank change [no rank] -> [2]", "Ready for the street."], notes.map(&:note)
    assert notes.first.is_log
    assert_not notes.last.is_log
    assert_equal [ranger.id], purged
  end

  test "score! logs no audit note when the rank is unchanged" do
    ranger = person(:active_ranger)
    sign_up(ranger)
    TraineeStatus.create!(person_id: ranger.id, slot_id: @slot.id, status: TraineeStatus::STATUS_NOT_PASSED, rank: 2)
    session = dirt_session

    capture_role_purges do
      session.score!(ranger.id, score_form(session.trainee(ranger.id), status: TraineeStatus::STATUS_PASSED, rank: 2))
    end

    assert_empty TraineeNote.where(slot_id: @slot.id, is_log: true)
    assert_equal TraineeStatus::STATUS_PASSED, TraineeStatus.find_by(person_id: ranger.id, slot_id: @slot.id).status
  end

  test "score! ignores feedback_delivered on ART sessions" do
    green_dot = Position.create!(id: Position::GREEN_DOT_TRAINING, title: "Green Dot Training",
                                 type: Position::TYPE_TRAINING, active: true)
    art_slot = create_slot(green_dot, begins: Time.zone.local(YEAR, 8, 9, 9, 0, 0))
    ranger = person(:active_ranger)
    sign_up(ranger, art_slot)
    session = TrainingSession.new(art_slot, green_dot)

    capture_role_purges do
      session.score!(ranger.id, score_form(session.trainee(ranger.id), status: TraineeStatus::STATUS_PASSED, feedback_delivered: true))
    end

    assert_not TraineeStatus.find_by(person_id: ranger.id, slot_id: art_slot.id).feedback_delivered
  end

  test "status_counts counts each status, and a trainee with no row as pending" do
    {
      person(:active_ranger) => TraineeStatus::STATUS_PASSED,
      person(:inactive_ranger) => TraineeStatus::STATUS_NO_SHOW,
      person(:retired_ranger) => TraineeStatus::STATUS_NOT_PASSED,
      person(:auditor_ranger) => TraineeStatus::STATUS_PENDING
    }.each do |trainee, status|
      sign_up(trainee)
      TraineeStatus.create!(person_id: trainee.id, slot_id: @slot.id, status:)
    end
    sign_up(person(:prospective_ranger))
    session = dirt_session

    assert_equal({ TraineeStatus::STATUS_PENDING => 2, TraineeStatus::STATUS_PASSED => 1,
                   TraineeStatus::STATUS_NO_SHOW => 1, TraineeStatus::STATUS_NOT_PASSED => 1 },
                 session.status_counts)
    assert_equal session.trainees.size, session.status_counts.values.sum
    assert_equal 1, session.passed_count
  end

  test "score! saves each of the four statuses as given" do
    ranger = person(:active_ranger)
    sign_up(ranger)

    TraineeStatus::STATUSES.each do |status|
      session = dirt_session
      capture_role_purges { session.score!(ranger.id, score_form(session.trainee(ranger.id), status:)) }

      assert_equal status, TraineeStatus.find_by(person_id: ranger.id, slot_id: @slot.id).status
      assert_equal status, dirt_session.trainee(ranger.id).training_status
    end
  end

  # --- the score form rules --------------------------------------------------

  test "only a pass needs a rank, and the status must be one of the four" do
    pnv = person(:prospective_ranger)
    sign_up(pnv)
    PersonStatus.create!(person_id: pnv.id, old_status: Person::ALPHA, new_status: Person::PROSPECTIVE,
                         created_at: Time.zone.local(YEAR, 1, 1))
    trainee = dirt_session.trainee(pnv.id)

    [TraineeStatus::STATUS_PENDING, TraineeStatus::STATUS_NO_SHOW, TraineeStatus::STATUS_NOT_PASSED].each do |status|
      assert score_form(trainee, status:).valid?, "#{status} needs no rank"
    end
    [nil, "maybe"].each do |status|
      form = score_form(trainee, status:)
      assert_not form.valid?
      assert_includes form.errors[:status], "Choose a training result."
    end
  end

  test "a passing trainee who needs ranking must be ranked" do
    pnv = person(:prospective_ranger)
    sign_up(pnv)
    PersonStatus.create!(person_id: pnv.id, old_status: Person::ALPHA, new_status: Person::PROSPECTIVE,
                         created_at: Time.zone.local(YEAR, 1, 1))

    form = score_form(dirt_session.trainee(pnv.id), status: TraineeStatus::STATUS_PASSED)

    assert_not form.valid?
    assert form.errors[:rank].any?
  end

  test "a rank other than average needs a note unless one already exists" do
    pnv = person(:prospective_ranger)
    sign_up(pnv)

    # A fresh session per check -- the roster memo is per-request, and each
    # note mutation here simulates a new request.
    form = score_form(dirt_session.trainee(pnv.id), status: TraineeStatus::STATUS_NOT_PASSED, rank: 4)
    assert_not form.valid?
    assert form.errors[:note].any?

    form = score_form(dirt_session.trainee(pnv.id), status: TraineeStatus::STATUS_NOT_PASSED, rank: 4, note: "Argued with the trainers.")
    assert form.valid?

    TraineeNote.record(person_id: pnv.id, slot_id: @slot.id, note: "Prior concern noted.")
    form = score_form(dirt_session.trainee(pnv.id), status: TraineeStatus::STATUS_NOT_PASSED, rank: 4)
    assert form.valid?, "a prior trainer note satisfies the requirement"

    TraineeNote.where(person_id: pnv.id, slot_id: @slot.id).delete_all
    TraineeNote.record(person_id: pnv.id, slot_id: @slot.id, note: "system", is_log: true)
    form = score_form(dirt_session.trainee(pnv.id), status: TraineeStatus::STATUS_NOT_PASSED, rank: 3)
    assert_not form.valid?, "audit rows do not satisfy the note requirement"
  end

  test "average rank and no rank need no note" do
    ranger = person(:active_ranger)
    sign_up(ranger)
    session = dirt_session

    assert score_form(session.trainee(ranger.id), status: TraineeStatus::STATUS_PASSED, rank: 2).valid?
    assert score_form(session.trainee(ranger.id), status: TraineeStatus::STATUS_NOT_PASSED).valid?
  end

  # --- trainer bulk save -----------------------------------------------------

  test "save_trainer_statuses! saves roster rows and skips everything else" do
    trainer_slot = create_slot(@trainer_position, begins: Time.zone.local(YEAR, 8, 8, 8, 30, 0),
                               description: "Bright Eyes")
    trainer = person(:active_ranger)
    outsider = person(:echelon_ranger)
    sign_up(trainer, trainer_slot)
    unrelated_slot = create_slot(@trainer_position, begins: Time.zone.local(YEAR, 8, 20, 9, 0, 0),
                                 description: "Elsewhere")

    saved = dirt_session.save_trainer_statuses!(
      [
        { person_id: trainer.id, trainer_slot_id: trainer_slot.id,
          status: TrainerStatus::STATUS_ATTENDED, is_lead: "1" },
        # Not on the trainer slot's roster.
        { person_id: outsider.id, trainer_slot_id: trainer_slot.id,
          status: TrainerStatus::STATUS_ATTENDED, is_lead: "0" },
        # Not one of this session's matched trainer slots.
        { person_id: trainer.id, trainer_slot_id: unrelated_slot.id,
          status: TrainerStatus::STATUS_ATTENDED, is_lead: "0" }
      ]
    )

    assert_equal 1, saved
    statuses = TrainerStatus.where(slot_id: @slot.id)
    assert_equal 1, statuses.count
    row = statuses.first
    assert_equal trainer.id, row.person_id
    assert_equal TrainerStatus::STATUS_ATTENDED, row.status
    assert row.is_lead
  end

  test "save_trainer_statuses! rejects unknown statuses and updates existing rows" do
    trainer_slot = create_slot(@trainer_position, begins: Time.zone.local(YEAR, 8, 8, 8, 30, 0),
                               description: "Bright Eyes")
    trainer = person(:active_ranger)
    sign_up(trainer, trainer_slot)
    TrainerStatus.create!(person_id: trainer.id, slot_id: @slot.id, trainer_slot_id: trainer_slot.id,
                          status: TrainerStatus::STATUS_ATTENDED, is_lead: true)

    saved = dirt_session.save_trainer_statuses!(
      [
        { person_id: trainer.id, trainer_slot_id: trainer_slot.id, status: "bogus", is_lead: "1" },
        { person_id: trainer.id, trainer_slot_id: trainer_slot.id,
          status: TrainerStatus::STATUS_NO_SHOW, is_lead: "0" }
      ]
    )

    assert_equal 1, saved
    row = TrainerStatus.find_by(slot_id: @slot.id, person_id: trainer.id)
    assert_equal TrainerStatus::STATUS_NO_SHOW, row.status
    assert_not row.is_lead
  end
end
