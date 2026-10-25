# frozen_string_literal: true

require "test_helper"

# Scoring a trainee through the dialog: authorization, validations, the
# audit trail, the role-cache purge, and the author-only note rules.
class Training::Sessions::ScoresControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper
  include TrainingSlotTestHelper
  include TrainingSessionTestHelper
  include ActiveSupport::Testing::TimeHelpers

  setup do
    setup_training_session_world
    @trainee = person(:prospective_ranger)
    sign_up(@trainee, @dirt_slot)
    # A status history row makes the trainee prospective AT the session (an
    # unknown status would waive the ranking requirement).
    PersonStatus.create!(person_id: @trainee.id, old_status: Person::ALPHA,
                         new_status: Person::PROSPECTIVE,
                         created_at: Time.zone.local(YEAR, 1, 1))
  end

  teardown do
    teardown_training_session_world
  end

  def score_path
    dirt_session_path("score", @trainee.id.to_s)
  end

  test "mentors and VCs may not open or submit the score dialog" do
    sign_in_as(@mentor)

    get score_path
    assert_redirected_to me_root_path

    post score_path, params: { training_score_form: { status: TraineeStatus::STATUS_PASSED, rank: "2" } }
    assert_redirected_to me_root_path
    assert_nil TraineeStatus.find_by(person_id: @trainee.id, slot_id: @dirt_slot.id)
  end

  test "the dialog renders with the trainee's notes" do
    TraineeNote.record(person_id: @trainee.id, slot_id: @dirt_slot.id, note: "Earlier note.",
                       person_source_id: @dirt_trainer.id)
    sign_in_as(@dirt_trainer)

    get score_path, headers: { "Turbo-Frame" => "modal" }

    assert_response :success
    assert_match "Score #{@trainee.callsign}", response.body
    assert_match "Earlier note.", response.body
    assert_match "Was feedback delivered", response.body
  end

  test "ART dialogs omit the feedback question" do
    art_trainee = person(:auditor_ranger)
    sign_up(art_trainee, @art_slot)
    sign_in_as(@art_trainer)

    get art_session_path("score", art_trainee.id.to_s)

    assert_response :success
    assert_no_match(/Was feedback delivered/, response.body)
  end

  test "a valid score saves, logs the rank change, and refreshes the roster" do
    sign_in_as(@dirt_trainer)

    post score_path, params: {
      training_score_form: { status: TraineeStatus::STATUS_PASSED, rank: "2", note: "Ready.", feedback_delivered: "true" }
    }, as: :turbo_stream

    assert_response :success
    status = TraineeStatus.find_by(person_id: @trainee.id, slot_id: @dirt_slot.id)
    assert_equal TraineeStatus::STATUS_PASSED, status.status
    assert_equal 2, status.rank
    assert status.feedback_delivered
    notes = TraineeNote.where(person_id: @trainee.id, slot_id: @dirt_slot.id).order(:id)
    assert_equal ["rank change [no rank] -> [2]", "Ready."], notes.map(&:note)
    assert_match "trainees-section", response.body
    assert_match "session-stats", response.body
    assert_match "score saved", response.body
  end

  test "the dialog offers the four statuses, starting from the trainee's own" do
    TraineeStatus.create!(person_id: @trainee.id, slot_id: @dirt_slot.id, status: TraineeStatus::STATUS_NO_SHOW)
    sign_in_as(@dirt_trainer)

    get score_path, headers: { "Turbo-Frame" => "modal" }

    assert_response :success
    assert_select "select[name='training_score_form[status]'] option", count: 4
    assert_select "select[name='training_score_form[status]'] option[selected]", text: "No Show"
  end

  test "a no-show is saved as one, with no rank asked for" do
    sign_in_as(@dirt_trainer)

    post score_path, params: { training_score_form: { status: TraineeStatus::STATUS_NO_SHOW } },
                     as: :turbo_stream

    assert_response :success
    assert_equal TraineeStatus::STATUS_NO_SHOW,
                 TraineeStatus.find_by(person_id: @trainee.id, slot_id: @dirt_slot.id).status
  end

  test "a status outside the four is refused" do
    sign_in_as(@dirt_trainer)

    post score_path, params: { training_score_form: { status: "maybe" } }, as: :turbo_stream

    assert_response :unprocessable_entity
    assert_match "Choose a training result.", response.body
    assert_nil TraineeStatus.find_by(person_id: @trainee.id, slot_id: @dirt_slot.id)
  end

  test "a non-hash score param is refused like an empty form rather than raising" do
    sign_in_as(@dirt_trainer)

    post score_path, params: { training_score_form: "x" }, as: :turbo_stream

    assert_response :unprocessable_entity
    assert_match "Choose a training result.", response.body
    assert_nil TraineeStatus.find_by(person_id: @trainee.id, slot_id: @dirt_slot.id)
  end

  test "a passing non-active without a rank is rejected with the error shown" do
    sign_in_as(@dirt_trainer)

    post score_path, params: { training_score_form: { status: TraineeStatus::STATUS_PASSED } }, as: :turbo_stream

    assert_response :unprocessable_entity
    assert_match "must be ranked", response.body
    assert_nil TraineeStatus.find_by(person_id: @trainee.id, slot_id: @dirt_slot.id)
  end

  test "a rank other than average without any note is rejected" do
    sign_in_as(@dirt_trainer)

    post score_path, params: { training_score_form: { status: TraineeStatus::STATUS_NOT_PASSED, rank: "4" } }, as: :turbo_stream

    assert_response :unprocessable_entity
    assert_match "rank other than 2", response.body
  end

  test "scoring a person who is not signed up closes with an error toast" do
    sign_in_as(@dirt_trainer)

    post dirt_session_path("score", person(:auditor_ranger).id.to_s),
         params: { training_score_form: { status: TraineeStatus::STATUS_NOT_PASSED } }, as: :turbo_stream

    assert_response :success
    assert_match "not signed up", response.body
    assert_nil TraineeStatus.find_by(person_id: person(:auditor_ranger).id, slot_id: @dirt_slot.id)
  end

  # --- notes ----------------------------------------------------------------

  test "only the author may edit or delete a note, and audit rows never can be" do
    mine = TraineeNote.record(person_id: @trainee.id, slot_id: @dirt_slot.id, note: "Mine.",
                              person_source_id: @dirt_trainer.id)
    theirs = TraineeNote.record(person_id: @trainee.id, slot_id: @dirt_slot.id, note: "Theirs.",
                                person_source_id: @admin.id)
    log = TraineeNote.record(person_id: @trainee.id, slot_id: @dirt_slot.id, note: "audit",
                             is_log: true, person_source_id: @dirt_trainer.id)
    sign_in_as(@dirt_trainer)

    patch dirt_session_path("notes", mine.id.to_s),
          params: { trainee_note: { note: "Mine, edited." } }, as: :turbo_stream
    assert_response :success
    assert_equal "Mine, edited.", mine.reload.note

    patch dirt_session_path("notes", theirs.id.to_s),
          params: { trainee_note: { note: "Hijacked." } }, as: :turbo_stream
    assert_equal "Theirs.", theirs.reload.note
    assert_match "Only the trainer who wrote a note", response.body

    delete dirt_session_path("notes", log.id.to_s), as: :turbo_stream
    assert TraineeNote.exists?(log.id), "audit rows are immutable"

    delete dirt_session_path("notes", mine.id.to_s), as: :turbo_stream
    assert_not TraineeNote.exists?(mine.id)
  end
end
