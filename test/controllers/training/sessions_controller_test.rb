# frozen_string_literal: true

require "test_helper"

# Training > Sessions landing: the TrainingPolicy view gate (NOT the looser
# Ember client guard), position resolution, and the rendered session list.
class Training::SessionsControllerTest < ActionDispatch::IntegrationTest
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
    @green_dot = Position.create!(id: Position::GREEN_DOT_TRAINING, title: "Green Dot Training",
                                  type: Position::TYPE_TRAINING, active: true)
    @green_dot_trainer = Position.create!(id: Position::GREEN_DOT_TRAINER, title: "Green Dot Trainer",
                                          type: Position::TYPE_TRAINING, active: true)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::TRAINER, "Trainer")
    ensure_role(Role::MENTOR, "Mentor")
    ensure_role(Role::VC, "VC")
    ensure_role(Role::ART_TRAINER, "ART Trainer")
    ensure_role(Role::ART_TRAINER_BASE | Position::GREEN_DOT_TRAINING, "Green Dot Interface")

    @admin = person(:active_ranger)
    @trainer = person(:echelon_ranger)
    @art_trainer = person(:retired_ranger)
    @outsider = person(:inactive_ranger)

    grant_role(@admin, Role::ADMIN)
    grant_role(@trainer, Role::TRAINER)
    grant_role(@art_trainer, Role::ART_TRAINER_BASE | Position::GREEN_DOT_TRAINING)
  end

  teardown do
    Current.reset
    Rails.cache.clear
    travel_back
  end

  # --- who may look ---------------------------------------------------------

  test "an admin may view any training" do
    sign_in_as(@admin)

    get training_path("in-person")
    assert_response :success
    assert_select "h1", text: /Training Sessions/

    get training_path("green-dot")
    assert_response :success
  end

  test "Trainer, Mentor, and VC may view In-Person Training" do
    sign_in_as(@trainer)
    get training_path("in-person")
    assert_response :success

    [Role::MENTOR, Role::VC].each do |role|
      viewer = person(:prospective_ranger)
      PersonRole.where(person_id: viewer.id).delete_all
      grant_role(viewer, role)
      sign_in_as(viewer)

      get training_path("in-person")
      assert_response :success, "role #{role} should view dirt training"
    end
  end

  test "the composed ART interface role views its own ART only" do
    sign_in_as(@art_trainer)

    get training_path("green-dot")
    assert_response :success

    get training_path("in-person")
    assert_redirected_to me_root_path
  end

  test "dirt roles and the plain ART Trainer role grant nothing on an ART" do
    grant_role(@trainer, Role::ART_TRAINER)
    sign_in_as(@trainer)

    get training_path("green-dot")

    assert_redirected_to me_root_path
    assert_match(/not authorized/, flash[:error])
  end

  test "a person with no training roles is turned away" do
    sign_in_as(@outsider)

    get training_path("in-person")

    assert_redirected_to me_root_path
  end

  # --- resolution -----------------------------------------------------------

  test "an unknown slug -- including an old numeric id -- is turned away, not crashed on" do
    sign_in_as(@admin)

    get training_path(999_999)

    assert_redirected_to me_root_path
    assert_equal "Training position not found.", flash[:error]
  end

  test "a trainer position is not a training interface" do
    sign_in_as(@admin)

    get training_path("green-dot-trainer")

    assert_redirected_to me_root_path
    assert_equal "Training position not found.", flash[:error]
  end

  test "a non-training position is not a training interface" do
    sign_in_as(@admin)

    get training_path("ood-officer-of-the-day")

    assert_redirected_to me_root_path
    assert_equal "Training position not found.", flash[:error]
  end

  test "an inactive training still resolves for historical data" do
    @green_dot.update!(active: false)
    sign_in_as(@admin)

    get training_path("green-dot")

    assert_response :success
  end

  # --- the session list -----------------------------------------------------

  test "sessions split into upcoming and past sections" do
    create_slot(@green_dot, begins: Time.zone.local(YEAR, 6, 1, 9, 0, 0), description: "June Session")
    create_slot(@green_dot, begins: Time.zone.local(YEAR, 9, 1, 9, 0, 0), description: "September Session")
    sign_in_as(@art_trainer)

    get training_path("green-dot")

    assert_response :success
    body = response.body
    upcoming_index = body.index("In Progress &amp; Upcoming Sessions")
    past_index = body.index("Past Sessions")
    assert upcoming_index < body.index("September Session")
    assert body.index("September Session") < past_index
    assert past_index < body.index("June Session")
  end

  test "a full session is flagged and an inactive one explains itself" do
    create_slot(@green_dot, begins: Time.zone.local(YEAR, 9, 1, 9, 0, 0),
                max: 2, signed_up: 2)
    create_slot(@green_dot, begins: Time.zone.local(YEAR, 9, 2, 9, 0, 0),
                active: false)
    sign_in_as(@art_trainer)

    get training_path("green-dot")

    assert_response :success
    assert_select ".badge", text: "FULL", count: 1
    assert_match(/sign-ups are disabled/, response.body)
  end

  test "matched trainer groups list callsigns; unmatched sessions teach the rule" do
    matched = create_slot(@green_dot, begins: Time.zone.local(YEAR, 9, 1, 9, 0, 0), description: "Bright Eyes")
    trainer_slot = create_slot(@green_dot_trainer, begins: Time.zone.local(YEAR, 9, 1, 8, 30, 0),
                               description: "Bright Eyes")
    PersonSlot.create!(person_id: @trainer.id, slot_id: trainer_slot.id)
    TrainerStatus.create!(person_id: @trainer.id, slot_id: matched.id,
                          trainer_slot_id: trainer_slot.id, is_lead: true)
    create_slot(@green_dot, begins: Time.zone.local(YEAR, 9, 2, 9, 0, 0), description: "Unmatched")
    sign_in_as(@art_trainer)

    get training_path("green-dot")

    assert_response :success
    assert_match(@trainer.callsign, response.body)
    assert_match(/\(lead\)/, response.body)
    assert_match(/No trainer slots were found/, response.body)
  end

  test "the year parameter scopes the list" do
    create_slot(@green_dot, begins: Time.zone.local(YEAR - 1, 6, 1, 9, 0, 0), description: "Last Year Session")
    sign_in_as(@art_trainer)

    get training_path("green-dot")
    assert_no_match(/Last Year Session/, response.body)

    get training_path("green-dot", year: YEAR - 1)
    assert_match(/Last Year Session/, response.body)
  end

  test "empty years render both empty states" do
    sign_in_as(@art_trainer)

    get training_path("green-dot")

    assert_response :success
    assert_match(/No upcoming sessions were found/, response.body)
    assert_match(/No past sessions were found/, response.body)
  end

  # --- menus ----------------------------------------------------------------

  test "the sidebar renders the position's own category" do
    sign_in_as(@art_trainer)

    get training_path("green-dot")

    assert_response :success
    assert_select "h6", text: "ART Green Dot"
    assert_select "a[href=?]", "/training/green-dot", text: /Sessions/
  end

  test "the mega menu lists only the trainings the viewer may see" do
    sign_in_as(@art_trainer)
    get me_menu_path
    assert_response :success
    assert_match(/ART Green Dot/, response.body)
    assert_no_match(/In-Person Training/, response.body)

    sign_in_as(@trainer)
    get me_menu_path
    assert_match(/In-Person Training/, response.body)
    assert_no_match(/ART Green Dot/, response.body)
  end

  # --- mega menu favorites and recents ----------------------------------------

  STREAM = { "Accept" => "text/vnd.turbo-stream.html" }.freeze

  test "a trainer can star the training's links; an outsider cannot" do
    sign_in_as(@trainer)
    get me_menu_path
    assert_select "section[data-panel='in-person-training'] .mega-menu-item " \
                  "button.mega-menu-star#mega-star-in-person-training-training-in-person-capacity"

    assert_difference "PersonFavorite.count", 1 do
      post me_toggle_favorite_path(path: "/training/in-person/capacity"), headers: STREAM
    end
    assert_response :success

    # The category gate also gates its links' stars
    sign_in_as(@outsider)
    assert_no_difference "PersonFavorite.count" do
      post me_toggle_favorite_path(path: "/training/in-person/capacity"), headers: STREAM
    end
    assert_response :unprocessable_content
  end

  test "visiting a training menu page records it for Recently Visited, and nothing else does" do
    trainer = @trainer
    slot = create_slot(@dirt, begins: Time.zone.local(YEAR, 6, 1, 9, 0, 0))
    sign_in_as(trainer)

    get training_capacity_path("in-person")
    assert_response :success
    assert PersonPageVisit.exists?(person_id: trainer.id, path: "/training/in-person/capacity")

    # Successful pages that are not menu links stay out: the override matches
    # the exact menu path, never a prefix
    assert_no_difference "PersonPageVisit.count" do
      get training_session_path("in-person", slot.id)
      assert_response :success
      get training_capacity_path("in-person", format: :csv)
      assert_response :success
    end
  end

  # Every training has its own "Capacity": a title repeated within one list
  # names its category, a title alone in the list stays bare even though it
  # repeats elsewhere in the menu.
  test "repeated titles in Favorites and Recently Visited name their category" do
    in_person = "/training/in-person/capacity"
    green_dot = "/training/green-dot/capacity"
    [in_person, green_dot, "/training/green-dot/multiple-enrollments"].each do |path|
      PersonFavorite.create!(person_id: @admin.id, path:)
    end
    [in_person, green_dot].each { |path| PersonPageVisit.record(@admin.id, path) }
    sign_in_as(@admin)

    get me_menu_path
    assert_response :success
    assert_select "section[data-panel='favorites']" do
      assert_select ".mega-menu-item-cat", count: 2
      assert_select ".mega-menu-item-cat", text: "(In-Person Training)"
      assert_select ".mega-menu-item-cat", text: "(ART Green Dot)"
      assert_select "button.mega-menu-star[aria-label='Favorite Capacity (ART Green Dot)']"
      assert_select "button.mega-menu-star[aria-label='Favorite Capacity (In-Person Training)']"
      assert_select "button.mega-menu-star[aria-label='Favorite Multiple Enrollments']"
    end
    assert_select "section[data-panel='recent'] .mega-menu-item-cat", count: 2
  end
end
