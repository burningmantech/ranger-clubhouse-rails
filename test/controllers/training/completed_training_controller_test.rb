# frozen_string_literal: true

require "test_helper"

# Training > Completed Training: the shared view gate, the summary table, the
# per-session pages and their pager, and the trainees-only CSV export.
class Training::CompletedTrainingControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include TrainingSlotTestHelper
  include ActiveSupport::Testing::TimeHelpers

  YEAR = 2026

  setup do
    travel_to Time.zone.local(YEAR, 8, 10, 12, 0, 0)
    Rails.cache.clear
    Current.reset

    @dirt = Position.create!(id: Position::TRAINING, title: "Training",
                             type: Position::TYPE_TRAINING, active: true)
    @dirt_trainer = Position.create!(id: Position::TRAINER, title: "Trainer",
                                     type: Position::TYPE_TRAINING, active: true)
    @green_dot = Position.create!(id: Position::GREEN_DOT_TRAINING, title: "Green Dot Training",
                                  type: Position::TYPE_TRAINING, active: true)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::TRAINER, "Trainer")
    ensure_role(Role::VIEW_EMAIL, "View Email")
    ensure_role(Role::ART_TRAINER_BASE | Position::GREEN_DOT_TRAINING, "Green Dot Interface")

    @trainer = person(:echelon_ranger)
    @art_trainer = person(:retired_ranger)
    @outsider = person(:inactive_ranger)

    grant_role(@trainer, Role::TRAINER)
    grant_role(@art_trainer, Role::ART_TRAINER_BASE | Position::GREEN_DOT_TRAINING)
  end

  teardown do
    Current.reset
    Rails.cache.clear
    travel_back
  end

  test "the index summarizes every ended session and links to its page" do
    ended = create_slot(@dirt, begins: Time.zone.local(YEAR, 6, 1, 9, 0, 0), description: "Bright Eyes")
    TraineeStatus.create!(person_id: person(:active_ranger).id, slot_id: ended.id, status: TraineeStatus::STATUS_PASSED)
    unscored = create_slot(@dirt, begins: Time.zone.local(YEAR, 6, 8, 9, 0, 0), description: "Dim Eyes")
    upcoming = create_slot(@dirt, begins: Time.zone.local(YEAR, 9, 1, 9, 0, 0), description: "Late Eyes")

    sign_in_as(@trainer)
    get training_completed_training_path("in-person")

    assert_response :success
    assert_select "h1", text: /Completed Training/
    assert_select "a[href=?]", training_completed_training_session_path("in-person", ended.id, year: YEAR)
    assert_select "a[href=?]", training_completed_training_session_path("in-person", unscored.id, year: YEAR)
    # A session still to come is not part of a completion report.
    assert_select "a[href=?]", training_completed_training_session_path("in-person", upcoming.id, year: YEAR),
                  count: 0
    assert_select "td", text: "Dim Eyes"
  end

  test "the session page lists the trainees who passed and the trainers who attended" do
    slot = create_slot(@dirt, begins: Time.zone.local(YEAR, 6, 1, 9, 0, 0), description: "Bright Eyes")
    trainee = person(:active_ranger)
    TraineeStatus.create!(person_id: trainee.id, slot_id: slot.id, status: TraineeStatus::STATUS_PASSED)
    # Scored, did not pass -- must not appear.
    TraineeStatus.create!(person_id: person(:alpha_ranger).id, slot_id: slot.id, status: TraineeStatus::STATUS_NOT_PASSED)

    trainer_slot = create_slot(@dirt_trainer, begins: Time.zone.local(YEAR, 6, 1, 8, 30, 0),
                               description: "Bright Eyes")
    TrainerStatus.create!(person_id: @art_trainer.id, slot_id: slot.id,
                          trainer_slot_id: trainer_slot.id, status: TrainerStatus::STATUS_ATTENDED)

    sign_in_as(@trainer)
    get training_completed_training_session_path("in-person", slot.id)

    assert_response :success
    assert_select "a", text: trainee.callsign
    assert_select "a", text: @art_trainer.callsign
    assert_select "a", text: person(:alpha_ranger).callsign, count: 0
  end

  test "the pager walks the year's sessions and stops at both ends" do
    first = create_slot(@dirt, begins: Time.zone.local(YEAR, 6, 1, 9, 0, 0))
    middle = create_slot(@dirt, begins: Time.zone.local(YEAR, 6, 8, 9, 0, 0))
    last = create_slot(@dirt, begins: Time.zone.local(YEAR, 6, 15, 9, 0, 0))

    sign_in_as(@trainer)

    get training_completed_training_session_path("in-person", middle.id)
    assert_select "a[href=?]", training_completed_training_session_path("in-person", first.id, year: YEAR)
    assert_select "a[href=?]", training_completed_training_session_path("in-person", last.id, year: YEAR)
    # Each tooltip names its session in words. The time helper returns markup,
    # which an attribute prints as tags.
    assert_select "nav[aria-label='Session navigation'] a[title*='@ 09:00']", 2
    assert_select "a[title*='<']", count: 0

    get training_completed_training_session_path("in-person", first.id)
    assert_select "a[href=?]", training_completed_training_session_path("in-person", middle.id, year: YEAR)
    assert_select "a", text: "Previous Session", count: 0

    get training_completed_training_session_path("in-person", last.id)
    assert_select "a", text: "Next Session", count: 0
  end

  test "a slot outside this training redirects back to the index" do
    other = create_slot(@green_dot, begins: Time.zone.local(YEAR, 6, 1, 9, 0, 0))

    sign_in_as(@trainer)
    get training_completed_training_session_path("in-person", other.id)

    assert_redirected_to training_completed_training_path("in-person", year: YEAR)
    assert_match(/not found/, flash[:error])
  end

  test "the view gate matches the interface: ART trainers get their ART only" do
    sign_in_as(@art_trainer)

    get training_completed_training_path("green-dot")
    assert_response :success

    get training_completed_training_path("in-person")
    assert_redirected_to me_root_path
    assert_match(/not authorized/, flash[:error])
  end

  test "an unauthorized person is turned away" do
    sign_in_as(@outsider)

    get training_completed_training_path("in-person")
    assert_redirected_to me_root_path
  end

  test "the CSV lists trainees only, never trainers" do
    slot = create_slot(@dirt, begins: Time.zone.local(YEAR, 6, 1, 9, 0, 0), description: "Bright Eyes")
    trainee = person(:active_ranger)
    TraineeStatus.create!(person_id: trainee.id, slot_id: slot.id, status: TraineeStatus::STATUS_PASSED)

    trainer_slot = create_slot(@dirt_trainer, begins: Time.zone.local(YEAR, 6, 1, 8, 30, 0),
                               description: "Bright Eyes")
    TrainerStatus.create!(person_id: @art_trainer.id, slot_id: slot.id,
                          trainer_slot_id: trainer_slot.id, status: TrainerStatus::STATUS_ATTENDED)

    sign_in_as(@trainer)
    get training_completed_training_path("in-person", format: :csv)

    assert_response :success
    assert_match "2026-in-person-completed-training.csv", response.headers["Content-Disposition"]

    lines = response.body.split("\n")
    assert_equal "Session,Location,Callsign", lines.first
    assert_equal "2026-06-01 09:00,Bright Eyes,#{trainee.callsign}", lines.second
    assert_equal 2, lines.size
  end

  test "the email column appears only for people who may see addresses" do
    slot = create_slot(@dirt, begins: Time.zone.local(YEAR, 6, 1, 9, 0, 0))
    trainee = person(:active_ranger)
    TraineeStatus.create!(person_id: trainee.id, slot_id: slot.id, status: TraineeStatus::STATUS_PASSED)

    sign_in_as(@trainer)
    get training_completed_training_path("in-person", format: :csv)
    assert_equal "Session,Location,Callsign", response.body.split("\n").first

    get training_completed_training_session_path("in-person", slot.id)
    assert_select "th", text: "Email", count: 0

    grant_role(@trainer, Role::VIEW_EMAIL)
    Rails.cache.clear
    sign_in_as(@trainer)

    get training_completed_training_path("in-person", format: :csv)
    lines = response.body.split("\n")
    assert_equal "Session,Location,Callsign,Email", lines.first
    assert_match trainee.email, lines.second

    get training_completed_training_session_path("in-person", slot.id)
    assert_select "th", text: "Email"
  end

  test "a year with no ended sessions says so" do
    sign_in_as(@trainer)

    get training_completed_training_path("in-person", year: YEAR - 1)

    assert_response :success
    assert_match "No sessions have ended in #{YEAR - 1}.", response.body
  end

  # The Sessions item claims only its session/ subtree, so a completed-training
  # page must light its own sidebar item -- including the per-session page.
  test "the sidebar marks Completed Training active on both pages" do
    slot = create_slot(@dirt, begins: Time.zone.local(YEAR, 6, 1, 9, 0, 0))

    sign_in_as(@trainer)

    get training_completed_training_path("in-person")
    assert_select "a[href=?][aria-current=true]", training_completed_training_path("in-person")

    get training_completed_training_session_path("in-person", slot.id)
    assert_select "a[href=?][aria-current=true]", training_completed_training_path("in-person")
    assert_select "a[href=?][aria-current=true]", training_path("in-person"), count: 0
  end
end
