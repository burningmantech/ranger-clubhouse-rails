# frozen_string_literal: true

require "test_helper"

# Training > Trained, No Rangering report: the shared view gate, who lands on
# the list (trainees who passed AND trainers who taught), who is filtered off
# it, the filter bar, the CSV export, and the three "nothing to show" states.
class Training::TrainedNoWorkControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include TrainingSlotTestHelper
  include ActiveSupport::Testing::TimeHelpers

  YEAR = 2026

  setup do
    travel_to Time.zone.local(YEAR, 10, 1, 12, 0, 0)
    Rails.cache.clear
    Current.reset

    @dirt = Position.create!(id: Position::TRAINING, title: "Training",
                             type: Position::TYPE_TRAINING, active: true)
    @dirt_trainer = Position.create!(id: Position::TRAINER, title: "Trainer",
                                     type: Position::TYPE_TRAINING, active: true)
    @green_dot = Position.create!(id: Position::GREEN_DOT_TRAINING, title: "Green Dot Training",
                                  type: Position::TYPE_TRAINING, active: true)

    # The working position this training qualifies people for.
    @shift = Position.create!(title: "Dirt", type: "Frontline", active: true,
                              no_training_required: false)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::TRAINER, "Trainer")
    ensure_role(Role::ART_TRAINER_BASE | Position::GREEN_DOT_TRAINING, "Green Dot Interface")

    @trainer = person(:echelon_ranger)
    @art_trainer = person(:retired_ranger)
    @outsider = person(:inactive_ranger)

    grant_role(@trainer, Role::TRAINER)
    grant_role(@art_trainer, Role::ART_TRAINER_BASE | Position::GREEN_DOT_TRAINING)

    # The schedule exists, so the report gets past its "nothing published" gate.
    create_slot(@shift, begins: Time.zone.local(YEAR, 8, 25, 18, 0, 0), description: "Dirt Shift")
    @session = create_slot(@dirt, begins: Time.zone.local(YEAR, 6, 1, 9, 0, 0), description: "Bright Eyes")
  end

  teardown do
    Current.reset
    Rails.cache.clear
    travel_back
  end

  # Signs person up to slot and records whether they passed it.
  def enroll(person, slot, status: TraineeStatus::STATUS_PASSED)
    PersonSlot.create!(person_id: person.id, slot_id: slot.id)
    TraineeStatus.create!(person_id: person.id, slot_id: slot.id, status:)
  end

  def ranger_shift(person, position = @shift, year: YEAR)
    Timesheet.create!(person_id: person.id, position_id: position.id,
                      on_duty: Time.zone.local(year, 8, 25, 18, 0, 0),
                      off_duty: Time.zone.local(year, 8, 25, 23, 0, 0),
                      additional_notes: "test")
  end

  test "someone who passed but never rangered is listed; someone who rangered is not" do
    slacker = person(:active_ranger)
    # Must hold an ACTIVE_STATUS, or the timesheet is not what keeps them off.
    diligent = person(:ranger_with_custom_gender)
    enroll(slacker, @session)
    enroll(diligent, @session)
    ranger_shift(diligent)

    sign_in_as(@trainer)
    get training_trained_no_work_path("in-person", year: YEAR)

    assert_response :success
    assert_select "h1", text: /Trained, No Rangering/
    assert_select "td,th", text: slacker.callsign
    assert_no_match diligent.callsign, response.body
    assert_match "Passed training", response.body
    assert_select "a[href=?]", training_session_path("in-person", @session.id, year: YEAR)
  end

  test "failing training keeps someone off the list" do
    failed = person(:active_ranger)
    enroll(failed, @session, status: TraineeStatus::STATUS_NOT_PASSED)

    sign_in_as(@trainer)
    get training_trained_no_work_path("in-person", year: YEAR)

    assert_response :success
    assert_match(/No one has passed/, response.body)
  end

  test "a trainer who taught but never rangered is listed (upstream's broken join, fixed)" do
    taught = person(:active_ranger)
    trainer_slot = create_slot(@dirt_trainer, begins: Time.zone.local(YEAR, 6, 1, 8, 30, 0),
                               description: "Bright Eyes")
    PersonSlot.create!(person_id: taught.id, slot_id: trainer_slot.id)
    TrainerStatus.create!(person_id: taught.id, slot_id: @session.id, trainer_slot_id: trainer_slot.id,
                          status: TrainerStatus::STATUS_ATTENDED)

    sign_in_as(@trainer)
    get training_trained_no_work_path("in-person", year: YEAR)

    assert_response :success
    assert_select "td,th", text: taught.callsign
    assert_match "Taught session", response.body
  end

  test "a trainer who no-showed their own session is not counted as trained" do
    no_show = person(:active_ranger)
    trainer_slot = create_slot(@dirt_trainer, begins: Time.zone.local(YEAR, 6, 1, 8, 30, 0),
                               description: "Bright Eyes")
    PersonSlot.create!(person_id: no_show.id, slot_id: trainer_slot.id)
    TrainerStatus.create!(person_id: no_show.id, slot_id: @session.id, trainer_slot_id: trainer_slot.id,
                          status: TrainerStatus::STATUS_NO_SHOW)

    sign_in_as(@trainer)
    get training_trained_no_work_path("in-person", year: YEAR)

    assert_response :success
    assert_match(/No one has passed/, response.body)
  end

  test "a position that does not require training does not excuse anyone" do
    no_training = Position.create!(title: "Social", type: "Frontline", active: true,
                                   no_training_required: true)
    slacker = person(:active_ranger)
    enroll(slacker, @session)
    ranger_shift(slacker, no_training)

    sign_in_as(@trainer)
    get training_trained_no_work_path("in-person", year: YEAR)

    assert_response :success
    assert_select "td,th", text: slacker.callsign
  end

  test "a locked status keeps someone off the list" do
    bonked = person(:bonked_ranger)
    enroll(bonked, @session)

    sign_in_as(@trainer)
    get training_trained_no_work_path("in-person", year: YEAR)

    assert_response :success
    assert_match(/Everyone who trained/, response.body)
  end

  test "the filters narrow the list by status and callsign" do
    active = person(:active_ranger)     # TestRanger
    retired = person(:retired_ranger)   # RetiredRanger
    enroll(active, @session)
    enroll(retired, @session)

    sign_in_as(@trainer)

    get training_trained_no_work_path("in-person", year: YEAR)
    assert_select "td,th", text: active.callsign
    assert_select "td,th", text: retired.callsign

    get training_trained_no_work_path("in-person", year: YEAR, status: Person::RETIRED)
    assert_select "td,th", text: retired.callsign
    assert_select "td,th", text: active.callsign, count: 0

    get training_trained_no_work_path("in-person", year: YEAR, callsign: "testrang")
    assert_select "td,th", text: active.callsign
    assert_select "td,th", text: retired.callsign, count: 0

    # A filter that matches no one still reports the season totals.
    get training_trained_no_work_path("in-person", year: YEAR, callsign: "no one")
    assert_match(/No one matched the current filters/, response.body)
  end

  test "the qualified-via filter separates trainers from trainees" do
    trainee = person(:active_ranger)
    enroll(trainee, @session)

    both = person(:ranger_with_custom_gender)
    enroll(both, @session)
    trainer_slot = create_slot(@dirt_trainer, begins: Time.zone.local(YEAR, 6, 1, 8, 30, 0),
                               description: "Bright Eyes")
    PersonSlot.create!(person_id: both.id, slot_id: trainer_slot.id)
    TrainerStatus.create!(person_id: both.id, slot_id: @session.id, trainer_slot_id: trainer_slot.id,
                          status: TrainerStatus::STATUS_ATTENDED)

    sign_in_as(@trainer)

    # Someone who did both belongs to either side of the filter.
    get training_trained_no_work_path("in-person", year: YEAR, via: "taught")
    assert_select "td,th", text: both.callsign
    assert_select "td,th", text: trainee.callsign, count: 0
    assert_match "Qualified Via: Taught session", response.body

    get training_trained_no_work_path("in-person", year: YEAR, via: "passed")
    assert_select "td,th", text: both.callsign
    assert_select "td,th", text: trainee.callsign

    # The choice counts overlap because that person shows under both.
    assert_select "option", text: "Passed training (2)"
    assert_select "option", text: "Taught session (1)"
  end

  test "a training with no trainers never offers the taught choice" do
    enroll(person(:active_ranger), @session)

    sign_in_as(@trainer)
    get training_trained_no_work_path("in-person", year: YEAR)

    assert_response :success
    assert_select "option", text: "Passed training (1)"
    assert_select "option", text: /Taught session/, count: 0
  end

  test "the CSV export carries the whole report, not the filtered view" do
    active = person(:active_ranger)
    retired = person(:retired_ranger)
    enroll(active, @session)
    enroll(retired, @session)

    sign_in_as(@trainer)
    get training_trained_no_work_path("in-person", year: YEAR, format: :csv, callsign: "no one")

    assert_response :success
    lines = response.body.split("\n")
    assert_equal "Callsign,Status,Qualified Via,Session,Timezone,Description", lines.first
    assert_equal 3, lines.size
    assert_match(/#{active.callsign},active,Passed,#{YEAR}-06-01 09:00,/, response.body)
  end

  test "an unpublished schedule and a misconfigured position each say so" do
    sign_in_as(@trainer)

    Slot.where(position_id: @shift.id).destroy_all
    get training_trained_no_work_path("in-person", year: YEAR)
    assert_match(/Nothing has been scheduled/, response.body)

    @shift.update!(active: false)
    get training_trained_no_work_path("in-person", year: YEAR)
    assert_match(/no working positions/, response.body)
  end

  test "the view gate matches the interface: ART trainers get their ART only" do
    sign_in_as(@art_trainer)

    get training_trained_no_work_path("green-dot", year: YEAR)
    assert_response :success
    assert_select "h1", text: /Green Dot Training/

    get training_trained_no_work_path("in-person", year: YEAR)
    assert_redirected_to me_root_path
    assert_match(/not authorized/, flash[:error])
  end

  test "an unauthorized person is turned away" do
    sign_in_as(@outsider)

    get training_trained_no_work_path("in-person", year: YEAR)
    assert_redirected_to me_root_path
    assert_match(/not authorized/, flash[:error])
  end
end
