# frozen_string_literal: true

require "test_helper"

# Roster adjustments and the trainer attendance bulk save. Dirt roster
# changes need admin or the DIRECTLY assigned Trainer role -- a Trainer
# Seasonal masquerade is refused.
class Training::Sessions::RostersControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper
  include TrainingSlotTestHelper
  include TrainingSessionTestHelper
  include ActiveSupport::Testing::TimeHelpers

  setup do
    setup_training_session_world
    @candidate = person(:prospective_ranger)
    PersonPosition.create!(person_id: @candidate.id, position_id: @dirt.id)
  end

  teardown do
    teardown_training_session_world
  end

  test "search finds people and excludes barred statuses" do
    sign_in_as(@dirt_trainer)

    get dirt_session_path("roster/new", kind: "trainee", q: @candidate.callsign),
        headers: { "Turbo-Frame" => "modal" }

    assert_response :success
    assert_match @candidate.callsign, response.body
    # The add form must escape the modal frame or a successful add's redirect
    # would only blank the dialog and leave the roster stale.
    assert_select "form[action*=?][data-turbo-frame=?]", "/roster", "_top"

    get dirt_session_path("roster/new", kind: "trainee", q: person(:deceased_ranger).callsign)
    assert_match(/No one matched/, response.body)
  end

  test "an old email address finds the person it belonged to" do
    ensure_role(Role::VIEW_EMAIL, "View Email")
    grant_role(@dirt_trainer, Role::VIEW_EMAIL)
    EmailHistory.create!(person_id: @candidate.id, email: "former.candidate@example.com")
    sign_in_as(@dirt_trainer)

    get dirt_session_path("roster/new", kind: "trainee", q: "former.candidate@example.com"),
        headers: { "Turbo-Frame" => "modal" }

    assert_response :success
    assert_select "td", text: @candidate.desired_full_name
  end

  test "an email search leaves out the statuses the dialog excludes" do
    ensure_role(Role::VIEW_EMAIL, "View Email")
    grant_role(@dirt_trainer, Role::VIEW_EMAIL)
    sign_in_as(@dirt_trainer)

    get dirt_session_path("roster/new", kind: "trainee", q: person(:retired_ranger).email),
        headers: { "Turbo-Frame" => "modal" }

    assert_match(/No one matched/, response.body)
  end

  test "an excluded status cannot be added, even by force" do
    retired = person(:retired_ranger)
    sign_in_as(@dirt_trainer)

    post dirt_session_path("roster"), params: { person_id: retired.id, kind: "trainee", force: "1" }

    assert_redirected_to dirt_session_path
    assert_equal "RetiredRanger is retired, so they cannot be added to a training session.", flash[:error]
    assert_not PersonSlot.have_slot?(retired.id, @dirt_slot.id)
  end

  test "a directly-assigned trainer adds a trainee through the blocker force flow" do
    sign_in_as(@dirt_trainer)

    # The candidate has unmet sign-up requirements, so the first attempt
    # comes back blocked with the force option (the upstream confirm step).
    post dirt_session_path("roster"), params: { person_id: @candidate.id, kind: "trainee" },
         as: :turbo_stream
    assert_response :unprocessable_entity
    assert_match "Add Anyway", response.body

    post dirt_session_path("roster"),
         params: { person_id: @candidate.id, kind: "trainee", force: "1" }

    assert_redirected_to dirt_session_path
    assert PersonSlot.have_slot?(@candidate.id, @dirt_slot.id)
    follow_redirect!
    assert_match @candidate.callsign, response.body
  end

  test "a Trainer Seasonal masquerade may not adjust the dirt roster" do
    # The masquerade: TRAINER arrives via a position's role grant, never a
    # direct person_role assignment.
    seasonal = person(:alpha_ranger)
    seasonal_position = Position.create!(title: "Trainer Seasonal", active: true)
    PositionRole.create!(position_id: seasonal_position.id, role_id: Role::TRAINER)
    PersonPosition.create!(person_id: seasonal.id, position_id: seasonal_position.id)
    RoleManager.purge_person(seasonal.id)
    sign_in_as(seasonal)

    # The derived TRAINER role views and manages the page...
    get dirt_session_path
    assert_response :success

    # ...but may not touch the roster.
    post dirt_session_path("roster"), params: { person_id: @candidate.id, kind: "trainee" }

    assert_redirected_to me_root_path
    assert_not PersonSlot.have_slot?(@candidate.id, @dirt_slot.id)
  end

  test "any ART trainer may adjust the ART roster" do
    PersonPosition.create!(person_id: @candidate.id, position_id: @green_dot.id)
    sign_in_as(@art_trainer)

    post art_session_path("roster"),
         params: { person_id: @candidate.id, kind: "trainee", force: "1" }

    assert_redirected_to art_session_path
    assert PersonSlot.have_slot?(@candidate.id, @art_slot.id)
  end

  test "a full session comes back blocked with a force option that works" do
    @dirt_slot.update!(max: 0)
    sign_in_as(@admin)

    post dirt_session_path("roster"), params: { person_id: @candidate.id, kind: "trainee" },
         as: :turbo_stream

    assert_response :unprocessable_entity
    assert_match "Could Not Add", response.body
    assert_match "Add Anyway", response.body
    assert_not PersonSlot.have_slot?(@candidate.id, @dirt_slot.id)

    post dirt_session_path("roster"),
         params: { person_id: @candidate.id, kind: "trainee", force: "1" }

    assert_redirected_to dirt_session_path
    assert PersonSlot.have_slot?(@candidate.id, @dirt_slot.id)
  end

  # Regression: Scheduling::Signup's enrollment helpers were called without a
  # receiver, so any add to a prevention-enabled training slot (every real
  # dirt session) crashed with NoMethodError instead of rendering the blocked
  # dialog. The lib-level verdict is pinned in signup_characterization_test.
  test "adding to a prevention-enabled session renders the blocked dialog, never a 500" do
    @dirt.update!(prevent_multiple_enrollments: true)
    other_session = create_slot(@dirt, begins: Time.zone.local(YEAR, 8, 15, 9, 0, 0),
                                description: "Elsewhere")
    sign_up(@candidate, other_session)
    sign_in_as(@admin)

    post dirt_session_path("roster"), params: { person_id: @candidate.id, kind: "trainee" },
         as: :turbo_stream

    assert_response :unprocessable_entity
    assert_match "Could Not Add", response.body
    assert_not PersonSlot.have_slot?(@candidate.id, @dirt_slot.id)

    post dirt_session_path("roster"),
         params: { person_id: @candidate.id, kind: "trainee", force: "1" }

    assert_redirected_to dirt_session_path
    assert PersonSlot.have_slot?(@candidate.id, @dirt_slot.id)
  end

  test "trainers join their group's slot, never an arbitrary one" do
    trainer_slot = create_slot(@dirt_trainer_position, begins: Time.zone.local(YEAR, 8, 8, 8, 30, 0),
                               description: "Bright Eyes")
    unrelated = create_slot(@dirt_trainer_position, begins: Time.zone.local(YEAR, 8, 20, 9, 0, 0),
                            description: "Elsewhere")
    joiner = person(:auditor_ranger)
    PersonPosition.create!(person_id: joiner.id, position_id: @dirt_trainer_position.id)
    sign_in_as(@admin)

    post dirt_session_path("roster"),
         params: { person_id: joiner.id, kind: "trainer", trainer_slot_id: unrelated.id, force: "1" }

    assert_redirected_to dirt_session_path
    assert PersonSlot.have_slot?(joiner.id, trainer_slot.id),
           "the request's stray slot id must fall back to the matched group"
    assert_not PersonSlot.have_slot?(joiner.id, unrelated.id)
  end

  test "removal takes a signed-up person off the roster" do
    sign_up(@candidate, @dirt_slot)
    sign_in_as(@dirt_trainer)

    delete dirt_session_path("roster", @candidate.id.to_s, kind: "trainee")

    assert_redirected_to dirt_session_path
    assert_not PersonSlot.have_slot?(@candidate.id, @dirt_slot.id)
  end

  # --- trainer attendance bulk save ----------------------------------------

  test "the bulk save persists attendance and lead flags" do
    trainer_slot = create_slot(@dirt_trainer_position, begins: Time.zone.local(YEAR, 8, 8, 8, 30, 0),
                               description: "Bright Eyes")
    sign_up(@dirt_trainer, trainer_slot)
    sign_in_as(@dirt_trainer)

    post dirt_session_path("trainer-statuses"), params: {
      trainers: {
        "#{trainer_slot.id}-#{@dirt_trainer.id}" => {
          person_id: @dirt_trainer.id, trainer_slot_id: trainer_slot.id,
          status: TrainerStatus::STATUS_ATTENDED, is_lead: "1"
        }
      }
    }

    assert_redirected_to dirt_session_path
    row = TrainerStatus.find_by(slot_id: @dirt_slot.id, person_id: @dirt_trainer.id)
    assert_equal TrainerStatus::STATUS_ATTENDED, row.status
    assert row.is_lead
  end

  test "the bulk save drops rows that are not hashes rather than raising" do
    trainer_slot = create_slot(@dirt_trainer_position, begins: Time.zone.local(YEAR, 8, 8, 8, 30, 0),
                               description: "Bright Eyes")
    sign_up(@dirt_trainer, trainer_slot)
    sign_in_as(@dirt_trainer)

    post dirt_session_path("trainer-statuses"), params: { trainers: "x" }
    assert_redirected_to dirt_session_path

    post dirt_session_path("trainer-statuses"), params: {
      trainers: {
        "stray" => "x",
        "#{trainer_slot.id}-#{@dirt_trainer.id}" => {
          person_id: @dirt_trainer.id, trainer_slot_id: trainer_slot.id, status: TrainerStatus::STATUS_ATTENDED
        }
      }
    }
    assert_redirected_to dirt_session_path
    assert_equal TrainerStatus::STATUS_ATTENDED,
                 TrainerStatus.find_by(slot_id: @dirt_slot.id, person_id: @dirt_trainer.id).status
  end

  test "mentors may not save trainer attendance" do
    sign_in_as(@mentor)

    post dirt_session_path("trainer-statuses"), params: { trainers: {} }

    assert_redirected_to me_root_path
  end
end
