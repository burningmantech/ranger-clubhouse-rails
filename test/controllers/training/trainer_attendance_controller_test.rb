# frozen_string_literal: true

require "test_helper"

# Training > Trainer Attendance report: the shared view gate, the rendered
# table, and the CSV export shape.
class Training::TrainerAttendanceControllerTest < ActionDispatch::IntegrationTest
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

  test "a trainer sees each teaching sign-up with its status and session link" do
    session = create_slot(@dirt, begins: Time.zone.local(YEAR, 6, 1, 9, 0, 0), description: "Bright Eyes")
    trainer_slot = create_slot(@dirt_trainer, begins: Time.zone.local(YEAR, 6, 1, 8, 30, 0),
                               description: "Bright Eyes")
    taught = person(:active_ranger)
    PersonSlot.create!(person_id: taught.id, slot_id: trainer_slot.id)
    TrainerStatus.create!(person_id: taught.id, slot_id: session.id, trainer_slot_id: trainer_slot.id,
                          status: TrainerStatus::STATUS_ATTENDED)
    # No status record of their own -- pending.
    PersonSlot.create!(person_id: person(:alpha_ranger).id, slot_id: trainer_slot.id)

    sign_in_as(@trainer)
    get training_trainer_attendance_path("in-person")

    assert_response :success
    assert_select "h1", text: /Training Trainer Attendance/
    assert_select "a[href=?]", training_session_path("in-person", session.id), count: 2
    assert_match "Attended", response.body
    assert_match "Pending", response.body
    assert_select "td", text: /1 of 1/
  end

  test "the view gate matches the interface: ART trainers get their ART only" do
    sign_in_as(@art_trainer)

    get training_trainer_attendance_path("green-dot")
    assert_response :success
    assert_select "h1", text: /Green Dot Training Trainer Attendance/

    get training_trainer_attendance_path("in-person")
    assert_redirected_to me_root_path
    assert_match(/not authorized/, flash[:error])
  end

  test "an unauthorized person is turned away" do
    sign_in_as(@outsider)

    get training_trainer_attendance_path("in-person")
    assert_redirected_to me_root_path
  end

  test "the CSV carries the upstream columns, one row per teaching sign-up" do
    session = create_slot(@dirt, begins: Time.zone.local(YEAR, 6, 1, 9, 0, 0), description: "Bright Eyes")
    trainer_slot = create_slot(@dirt_trainer, begins: Time.zone.local(YEAR, 6, 1, 8, 30, 0),
                               description: "Bright Eyes")
    taught = person(:active_ranger)
    PersonSlot.create!(person_id: taught.id, slot_id: trainer_slot.id)
    TrainerStatus.create!(person_id: taught.id, slot_id: session.id, trainer_slot_id: trainer_slot.id,
                          status: TrainerStatus::STATUS_ATTENDED)

    sign_in_as(@trainer)
    get training_trainer_attendance_path("in-person", format: :csv)

    assert_response :success
    assert_match "2026-in-person-trainer-attendance.csv", response.headers["Content-Disposition"]

    lines = response.body.split("\n")
    assert_equal "Callsign,Date,Timezone,Type,Description,Attended", lines.first
    assert_equal "#{taught.callsign},2026-06-01 08:30,PDT,Trainer,Bright Eyes,attended", lines.second
  end

  test "a year with no trainers says so" do
    sign_in_as(@trainer)

    get training_trainer_attendance_path("in-person", year: YEAR - 1)

    assert_response :success
    assert_match "No trainers were found for #{YEAR - 1}.", response.body
  end
end
