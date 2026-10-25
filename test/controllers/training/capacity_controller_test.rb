# frozen_string_literal: true

require "test_helper"

# Training > Capacity report: the shared view gate, the rendered table (dash
# rule included), and the CSV export shape.
class Training::CapacityControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include TrainingSlotTestHelper
  include ReportCardTestHelper # assert_report_card / card_answer / assert_no_card_question
  include ActiveSupport::Testing::TimeHelpers

  YEAR = 2026

  setup do
    travel_to Time.zone.local(YEAR, 8, 10, 12, 0, 0)
    Rails.cache.clear
    Current.reset

    @dirt = Position.create!(id: Position::TRAINING, title: "Training",
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

  test "a trainer sees the report with dashes for sessions still to come" do
    ended = create_slot(@dirt, begins: Time.zone.local(YEAR, 6, 1, 9, 0, 0), description: "Bright Eyes")
    PersonSlot.create!(person_id: person(:active_ranger).id, slot_id: ended.id)
    TraineeStatus.create!(person_id: person(:active_ranger).id, slot_id: ended.id, status: TraineeStatus::STATUS_PASSED)
    upcoming = create_slot(@dirt, begins: Time.zone.local(YEAR, 9, 1, 9, 0, 0), description: "Dim Eyes")
    PersonSlot.create!(person_id: person(:alpha_ranger).id, slot_id: upcoming.id)

    sign_in_as(@trainer)
    get training_capacity_path("in-person")

    assert_response :success
    assert_select "h1", text: /Training Capacity/
    assert_select "th", text: "Bright Eyes"
    # The column is everyone short of a pass, not the not-passed status alone.
    assert_select "th[title=?]", "No-shows, not passed, and not yet scored", text: "Not Passed"
    assert_select "td", text: "—", count: 2
    assert_select "td", text: /\(unique\)/
  end

  # A heading's tooltip reaches a pointer and nothing else, so the card says what
  # the three noted headings count. Why a pass count is blank is said only while
  # a session is still to come.
  test "the card explains the noted headings, and the blank pass count while a session is unscored" do
    blank = "Why is a session's pass count blank?"
    create_slot(@dirt, begins: Time.zone.local(YEAR, 6, 1, 9, 0, 0), description: "Bright Eyes")
    upcoming = create_slot(@dirt, begins: Time.zone.local(YEAR, 9, 1, 9, 0, 0), description: "Dim Eyes")

    sign_in_as(@trainer)
    get training_capacity_path("in-person")

    assert_equal "No-shows, not passed, and not yet scored.", card_answer("What does “Not Passed” count?")
    assert_match(/after a session ends/, card_answer(blank))

    Slot.where(id: upcoming.id).delete_all
    get training_capacity_path("in-person")

    assert_report_card
    assert_no_card_question blank
  end

  test "the view gate matches the interface: ART trainers get their ART only" do
    sign_in_as(@art_trainer)

    get training_capacity_path("green-dot")
    assert_response :success
    assert_select "h1", text: /Green Dot Training Capacity/

    get training_capacity_path("in-person")
    assert_redirected_to me_root_path
    assert_match(/not authorized/, flash[:error])
  end

  test "an unauthorized person is turned away" do
    sign_in_as(@outsider)

    get training_capacity_path("in-person")
    assert_redirected_to me_root_path
  end

  # The Sessions item claims only its session/ subtree (String active_prefix),
  # so the sibling Capacity item wins its own page -- pin the server-rendered
  # active states on both pages.
  test "the sidebar marks Capacity active on the report and Sessions active on a session" do
    slot = create_slot(@dirt, begins: Time.zone.local(YEAR, 6, 1, 9, 0, 0))

    sign_in_as(@trainer)

    get training_capacity_path("in-person")
    assert_select "a[href=?][aria-current=true]", training_capacity_path("in-person")
    assert_select "a[href=?][aria-current=true]", training_path("in-person"), count: 0

    get training_session_path("in-person", slot.id)
    assert_select "a[href=?][aria-current=true]", training_path("in-person")
    assert_select "a[href=?][aria-current=true]", training_capacity_path("in-person"), count: 0
  end

  test "the CSV carries the upstream columns, blank pass cells, and the totals row" do
    ended = create_slot(@dirt, begins: Time.zone.local(YEAR, 6, 1, 9, 0, 0),
                        description: "Bright Eyes", max: 2)
    PersonSlot.create!(person_id: person(:active_ranger).id, slot_id: ended.id)
    TraineeStatus.create!(person_id: person(:active_ranger).id, slot_id: ended.id, status: TraineeStatus::STATUS_PASSED)
    upcoming = create_slot(@dirt, begins: Time.zone.local(YEAR, 9, 1, 9, 0, 0),
                           description: "Dim Eyes", max: 4)
    PersonSlot.create!(person_id: person(:alpha_ranger).id, slot_id: upcoming.id)
    PersonStatus.create!(person_id: person(:alpha_ranger).id, old_status: "prospective",
                         new_status: "alpha", created_at: Time.zone.local(YEAR, 1, 5))

    sign_in_as(@trainer)
    get training_capacity_path("in-person", format: :csv)

    assert_response :success
    assert_match "2026-in-person-capacity.csv", response.headers["Content-Disposition"]

    lines = response.body.split("\n")
    assert_equal "Training,Date,Timezone,% Filled,Seats,Signed Up,PNVs,Returning,Auditors,Passed,Not Passed,Trainers",
                 lines.first
    assert_equal "Bright Eyes,2026-06-01 09:00,PDT,50%,2,1,0,1,0,1,0,0", lines.second
    assert_equal "Dim Eyes,2026-09-01 09:00,PDT,25%,4,1,1,0,0,,,0", lines.third
    assert_equal ",Totals,,33%,6,2,1,1,0,1,0,0 (unique)", lines.fourth
  end

  # slot.begins is already local wall-clock; Slot#begins_adjusted converts it and
  # shifts any session outside the app zone. Pin the raw time against a Mountain
  # session, which begins_adjusted would push an hour late.
  test "the CSV date matches the page for a session outside the app timezone" do
    create_slot(@dirt, begins: Time.zone.local(YEAR, 6, 1, 17, 15, 0),
                       description: "Littleton, CO", timezone: "America/Denver")

    sign_in_as(@trainer)
    get training_capacity_path("in-person", format: :csv)

    assert_response :success
    assert_match(/^"Littleton, CO",2026-06-01 17:15,MDT,/, response.body)

    get training_capacity_path("in-person")
    assert_select "th", text: /Littleton, CO/
    assert_match(/Jun 1 @ 17:15 \(MDT\)/, response.body)
  end

  test "a year with no sessions says so" do
    sign_in_as(@trainer)

    get training_capacity_path("in-person", year: YEAR - 1)

    assert_response :success
    assert_match "No sessions were found for #{YEAR - 1}.", response.body
  end
end
