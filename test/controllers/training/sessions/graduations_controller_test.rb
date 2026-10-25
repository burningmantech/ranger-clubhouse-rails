# frozen_string_literal: true

require "test_helper"

# The graduation dialog and grant (ART graduate role only), plus the
# work history dialog it scopes.
class Training::Sessions::GraduationsControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper
  include TrainingSlotTestHelper
  include TrainingSessionTestHelper
  include ActiveSupport::Testing::TimeHelpers

  setup do
    setup_training_session_world
    Position.create!(id: Position::GREEN_DOT_MENTEE, title: "Green Dot Mentee", active: true)
    Position.create!(id: Position::SANCTUARY_MENTEE, title: "Sanctuary Mentee", active: true)
    Position.create!(id: Position::DIRT_GREEN_DOT, title: "Dirt - Green Dot", active: true)
    Position.create!(id: Position::DIRT, title: "Dirt", active: true)
    # The prospective_ranger fixture carries an Alpha timesheet whose
    # position row doesn't exist by default; WorkHistoryReport walks it.
    Position.create!(id: Position::ALPHA, title: "Alpha", active: true)

    @graduate_trainer = @art_trainer
    grant_role(@graduate_trainer, Role::ART_GRADUATE_BASE | Position::GREEN_DOT_TRAINING)

    @passed = person(:prospective_ranger)
    sign_up(@passed, @art_slot)
    TraineeStatus.create!(person_id: @passed.id, slot_id: @art_slot.id, status: TraineeStatus::STATUS_PASSED)
    3.times do |i|
      Timesheet.create!(person_id: @passed.id, position_id: Position::DIRT,
                        on_duty: Time.zone.local(YEAR - 1, 8, 25 + i, 9, 0, 0),
                        off_duty: Time.zone.local(YEAR - 1, 8, 25 + i, 16, 0, 0),
                        additional_notes: "requirements")
    end
    @passed.update!(years_as_ranger: [YEAR - 1])

    @failed = person(:past_prospective_ranger)
    sign_up(@failed, @art_slot)
    TraineeStatus.create!(person_id: @failed.id, slot_id: @art_slot.id, status: TraineeStatus::STATUS_NOT_PASSED)
  end

  teardown do
    teardown_training_session_world
  end

  test "an ART trainer without the graduate role is refused" do
    sign_in_as(@dirt_trainer)
    get art_session_path("graduation")
    assert_redirected_to me_root_path

    # Interface role alone is not enough either.
    other = person(:plate_collision_ranger)
    grant_role(other, Role::ART_TRAINER_BASE | Position::GREEN_DOT_TRAINING)
    sign_in_as(other)
    get art_session_path("graduation")
    assert_redirected_to me_root_path

    post art_session_path("graduation"), params: { person_ids: [@passed.id] }
    assert_redirected_to me_root_path
    assert_empty PersonPosition.where(person_id: @passed.id)
  end

  test "dirt graduation URLs are refused outright -- only ARTs graduate" do
    sign_in_as(@admin)

    get dirt_session_path("graduation")

    assert_redirected_to me_root_path
    assert_match(/not authorized/, flash[:error])
  end

  test "the dialog buckets candidates; a failed trainee is NOT eligible" do
    sign_in_as(@graduate_trainer)

    get art_session_path("graduation"), headers: { "Turbo-Frame" => "modal" }

    assert_response :success
    assert_match "Graduate Trainees", response.body
    assert_match @passed.callsign, response.body
    assert_match "Has not been marked as passed", response.body
    assert_select "input[type=checkbox][name='person_ids[]'][value=?]", @passed.id.to_s
    assert_select "input[type=checkbox][name='person_ids[]'][value=?]", @failed.id.to_s, count: 0
  end

  test "graduating grants the positions and reports per-person results" do
    sign_in_as(@graduate_trainer)

    post art_session_path("graduation"), params: { person_ids: [@passed.id, @failed.id] },
         as: :turbo_stream

    assert_response :success
    assert_match "Graduation Results", response.body
    granted = PersonPosition.where(person_id: @passed.id).pluck(:position_id)
    assert_includes granted, Position::GREEN_DOT_MENTEE
    assert_includes granted, Position::SANCTUARY_MENTEE
    assert_empty PersonPosition.where(person_id: @failed.id),
                 "a failed trainee is never granted positions"

    log = PersonPositionLog.where(person_id: @passed.id).last
    assert log.present?, "the grant is audited"
  end

  test "an empty selection re-renders the dialog with an error" do
    sign_in_as(@graduate_trainer)

    post art_session_path("graduation"), params: {}, as: :turbo_stream

    assert_response :unprocessable_entity
    assert_match "Pick at least one trainee", response.body
  end

  # to_i read "#{id}x" as the id and graduated that trainee.
  test "person ids that are not ids count as no selection" do
    sign_in_as(@graduate_trainer)

    post art_session_path("graduation"), params: { person_ids: ["", "abc", "#{@passed.id}x"] },
         as: :turbo_stream

    assert_response :unprocessable_entity
    assert_match "Pick at least one trainee", response.body
    assert_empty PersonPosition.where(person_id: @passed.id)
  end

  # --- work history ---------------------------------------------------------

  test "the work history dialog needs the graduate role and a roster member" do
    sign_in_as(@dirt_trainer)
    get art_session_path("work-history", @passed.id.to_s)
    assert_redirected_to me_root_path

    sign_in_as(@graduate_trainer)
    get art_session_path("work-history", @passed.id.to_s), headers: { "Turbo-Frame" => "modal" }
    assert_response :success
    assert_match "Work History — #{@passed.callsign}", response.body
    assert_match "Dirt", response.body

    get art_session_path("work-history", person(:plate_collision_ranger).id.to_s)
    assert_match "not signed up", response.body
  end

  test "the work history drill-down renders a cell's entries" do
    sign_in_as(@graduate_trainer)

    get art_session_path("work-history", @passed.id.to_s,
                         detail_position_id: Position::DIRT, detail_year: YEAR - 1)

    assert_response :success
    assert_select "turbo-frame#wh-detail" do
      assert_select "td", text: /7\.00|7:00|7/
    end
  end
end
