# frozen_string_literal: true

require "test_helper"

# Training > Untrained People report: the shared view gate, who lands in each
# blocker group, who is cleared off the list, the filter bar, the filtered
# copy-emails button, the CSV export, and the "nothing to show" states.
class Training::UntrainedPeopleControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include TrainingSlotTestHelper
  include ActiveSupport::Testing::TimeHelpers

  YEAR = 2026

  setup do
    travel_to Time.zone.local(YEAR, 7, 1, 12, 0, 0)
    Rails.cache.clear
    Current.reset

    @dirt = Position.create!(id: Position::TRAINING, title: "Training",
                             type: Position::TYPE_TRAINING, active: true)
    @dirt_trainer = Position.create!(id: Position::TRAINER, title: "Trainer",
                                     type: Position::TYPE_TRAINING, active: true)
    @green_dot = Position.create!(id: Position::GREEN_DOT_TRAINING, title: "Green Dot Training",
                                  type: Position::TYPE_TRAINING, active: true)

    # The working position this training qualifies people for.
    @shift_position = Position.create!(title: "Dirt", type: "Frontline", active: true,
                                       no_training_required: false)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::TRAINER, "Trainer")
    ensure_role(Role::ART_TRAINER_BASE | Position::GREEN_DOT_TRAINING, "Green Dot Interface")

    @trainer = person(:echelon_ranger)
    @art_trainer = person(:retired_ranger)
    @outsider = person(:inactive_ranger)

    grant_role(@trainer, Role::TRAINER)
    grant_role(@art_trainer, Role::ART_TRAINER_BASE | Position::GREEN_DOT_TRAINING)

    @shift = create_slot(@shift_position, begins: Time.zone.local(YEAR, 8, 25, 18, 0, 0),
                         description: "Dirt Shift")
    @session = create_slot(@dirt, begins: Time.zone.local(YEAR, 6, 1, 9, 0, 0),
                           description: "Bright Eyes")
  end

  teardown do
    Current.reset
    Rails.cache.clear
    travel_back
  end

  def sign_up(person, slot)
    PersonSlot.create!(person_id: person.id, slot_id: slot.id)
  end

  test "a shift sign-up without a training sign-up is listed; a pass clears someone entirely" do
    untrained = person(:active_ranger)
    passed = person(:ranger_with_custom_gender)
    sign_up(untrained, @shift)
    sign_up(passed, @shift)
    sign_up(passed, @session)
    TraineeStatus.create!(person_id: passed.id, slot_id: @session.id, status: TraineeStatus::STATUS_PASSED)

    sign_in_as(@trainer)
    get training_untrained_people_path("in-person", year: YEAR)

    assert_response :success
    assert_select "h1", text: /Untrained People/
    assert_match untrained.callsign, response.body
    assert_no_match passed.callsign, response.body
    assert_match "No training sign-up", response.body
    assert_match "Dirt Shift", response.body
  end

  test "a session sign-up in another training does not count for this one" do
    wrong_training = person(:active_ranger)
    gd_session = create_slot(@green_dot, begins: Time.zone.local(YEAR, 6, 2, 9, 0, 0),
                             description: "Green Dot Session")
    sign_up(wrong_training, @shift)
    sign_up(wrong_training, gd_session)

    sign_in_as(@trainer)
    get training_untrained_people_path("in-person", year: YEAR)

    assert_response :success
    assert_match wrong_training.callsign, response.body
    assert_match "No training sign-up", response.body
  end

  test "signed up but not passed shows their latest session, linked" do
    pending = person(:active_ranger)
    later_session = create_slot(@dirt, begins: Time.zone.local(YEAR, 6, 15, 9, 0, 0),
                                description: "Second Chance")
    sign_up(pending, @shift)
    sign_up(pending, @session)
    sign_up(pending, later_session)
    TraineeStatus.create!(person_id: pending.id, slot_id: @session.id, status: TraineeStatus::STATUS_NOT_PASSED)

    sign_in_as(@trainer)
    get training_untrained_people_path("in-person", year: YEAR)

    assert_response :success
    assert_match pending.callsign, response.body
    assert_match "Not passed yet", response.body
    assert_select "a[href=?]", training_session_path("in-person", later_session.id, year: YEAR)
    assert_select "a[href=?]", training_session_path("in-person", @session.id, year: YEAR), count: 0
  end

  test "a not-passed session sign-up without any shift sign-up stays off the list" do
    keen = person(:active_ranger)
    sign_up(keen, @session)

    sign_in_as(@trainer)
    get training_untrained_people_path("in-person", year: YEAR)

    assert_response :success
    assert_match(/Nothing to chase/, response.body)
  end

  test "a trainer sign-up counts as training; attending clears them" do
    teacher = person(:active_ranger)
    trainer_slot = create_slot(@dirt_trainer, begins: Time.zone.local(YEAR, 6, 1, 8, 30, 0),
                               description: "Bright Eyes")
    sign_up(teacher, @shift)
    sign_up(teacher, trainer_slot)

    sign_in_as(@trainer)
    get training_untrained_people_path("in-person", year: YEAR)
    assert_response :success
    assert_match teacher.callsign, response.body
    assert_match "Not passed yet", response.body
    # Their "session" is the trainer slot, which the session page would
    # reject -- shown, but never linked.
    assert_select "a[href=?]", training_session_path("in-person", trainer_slot.id, year: YEAR), count: 0

    TrainerStatus.create!(person_id: teacher.id, slot_id: @session.id, trainer_slot_id: trainer_slot.id,
                          status: TrainerStatus::STATUS_ATTENDED)
    get training_untrained_people_path("in-person", year: YEAR)
    assert_match(/Nothing to chase/, response.body)
  end

  test "the filters narrow the list by blocker and callsign" do
    untrained = person(:active_ranger)     # TestRanger
    pending = person(:retired_ranger)      # RetiredRanger
    sign_up(untrained, @shift)
    sign_up(pending, @shift)
    sign_up(pending, @session)

    sign_in_as(@trainer)

    get training_untrained_people_path("in-person", year: YEAR)
    assert_match untrained.callsign, response.body
    assert_match pending.callsign, response.body
    assert_select "option", text: "No training sign-up (1)"
    assert_select "option", text: "Not passed yet (1)"

    get training_untrained_people_path("in-person", year: YEAR,
                                       blocker: Training::UntrainedPeopleReport::NO_SIGNUP)
    assert_match untrained.callsign, response.body
    assert_no_match pending.callsign, response.body
    assert_match "Blocker: No training sign-up", response.body

    get training_untrained_people_path("in-person", year: YEAR, callsign: "retired")
    assert_match pending.callsign, response.body
    assert_no_match untrained.callsign, response.body

    # A filter that matches no one still reports the season totals.
    get training_untrained_people_path("in-person", year: YEAR, callsign: "no one")
    assert_match(/No one matched the current filters/, response.body)
  end

  test "the copy-emails button carries the filtered addresses" do
    untrained = person(:active_ranger)
    pending = person(:retired_ranger)
    sign_up(untrained, @shift)
    sign_up(pending, @shift)
    sign_up(pending, @session)

    sign_in_as(@trainer)

    get training_untrained_people_path("in-person", year: YEAR)
    assert_select "[data-copy-to-clipboard-content-value=?]",
                  "#{untrained.email}, #{pending.email}"

    get training_untrained_people_path("in-person", year: YEAR,
                                       blocker: Training::UntrainedPeopleReport::NOT_PASSED)
    assert_select "[data-copy-to-clipboard-content-value=?]", pending.email
  end

  test "the CSV export carries the whole report, one row per shift sign-up" do
    untrained = person(:active_ranger)
    second_shift = create_slot(@shift_position, begins: Time.zone.local(YEAR, 8, 26, 18, 0, 0),
                               description: "Dirt Shift Two")
    sign_up(untrained, @shift)
    sign_up(untrained, second_shift)

    sign_in_as(@trainer)
    get training_untrained_people_path("in-person", year: YEAR, format: :csv, callsign: "no one")

    assert_response :success
    lines = response.body.split("\n")
    assert_equal "Callsign,Blocker,Email,Training Session,Shift,Timezone,Description,Position", lines.first
    assert_equal 3, lines.size
    assert_match(/#{untrained.callsign},No training sign-up,#{untrained.email},,#{YEAR}-08-25 18:00,/, response.body)
    assert_match "Dirt Shift Two", response.body
  end

  test "no sessions, no shifts, and a misconfigured position each say so" do
    person_with_shift = person(:active_ranger)
    sign_up(person_with_shift, @shift)

    sign_in_as(@trainer)

    Slot.where(position_id: @dirt.id).destroy_all
    get training_untrained_people_path("in-person", year: YEAR)
    assert_match(/No Training sessions have been scheduled/, response.body)

    create_slot(@dirt, begins: Time.zone.local(YEAR, 6, 1, 9, 0, 0), description: "Bright Eyes")
    Slot.where(position_id: @shift_position.id).destroy_all
    get training_untrained_people_path("in-person", year: YEAR)
    assert_match(/No shifts requiring Training have been scheduled/, response.body)

    @shift_position.update!(active: false)
    get training_untrained_people_path("in-person", year: YEAR)
    assert_match(/no positions that require it/, response.body)
  end

  test "the view gate matches the interface: ART trainers get their ART only" do
    sign_in_as(@art_trainer)

    get training_untrained_people_path("green-dot", year: YEAR)
    assert_response :success
    assert_select "h1", text: /Green Dot Training/

    get training_untrained_people_path("in-person", year: YEAR)
    assert_redirected_to me_root_path
    assert_match(/not authorized/, flash[:error])
  end

  test "an unauthorized person is turned away" do
    sign_in_as(@outsider)

    get training_untrained_people_path("in-person", year: YEAR)
    assert_redirected_to me_root_path
    assert_match(/not authorized/, flash[:error])
  end
end
