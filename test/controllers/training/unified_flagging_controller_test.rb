# frozen_string_literal: true

require "test_helper"

# In-Person Training's read-only copy of the applicant pipeline. The page
# itself is the same shared template the /vc suite covers in depth
# (test/controllers/vc/unified_flagging_controller_test.rb) -- what is tested
# here is what differs: the two stacked gates, the In-Person-only restriction,
# and that no note controls render for anyone.
class Training::UnifiedFlaggingControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include IntakeTestHelper
  include ActiveSupport::Testing::TimeHelpers

  YEAR = 2026

  DENY_MESSAGE = "Admin or Intake role required to view unified flagging."

  setup do
    travel_to Time.zone.local(YEAR, 4, 16, 12, 0, 0)
    Rails.cache.clear
    Current.reset

    Position.create!(id: Position::TRAINING, title: "Training",
                     type: Position::TYPE_TRAINING, active: true)
    Position.create!(id: Position::GREEN_DOT_TRAINING, title: "Green Dot Training",
                     type: Position::TYPE_TRAINING, active: true)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::INTAKE, "Intake")
    ensure_role(Role::TRAINER, "Trainer")
    ensure_role(Role::VC, "Volunteer Coordinator")
    ensure_role(Role::ART_TRAINER_BASE | Position::GREEN_DOT_TRAINING, "Green Dot Interface")

    # Carries the full multi-year intake history in the fixtures, including a
    # 2026 personnel_rank of 4 -- the flag that quarantines a row.
    @flagged = person(:prospective_ranger)

    @admin = person(:auditor_ranger)
    # Passes the training tree's view gate AND holds Intake -- the intended
    # audience.
    @intake_trainer = person(:echelon_ranger)
    # Passes the tree's view gate but has no Intake role.
    @trainer = person(:active_ranger)
    # Holds Intake but nothing that admits them to the training tree.
    @intake_only = person(:ranger_with_custom_gender)
    @art_trainer = person(:retired_ranger)

    grant_role(@admin, Role::ADMIN)
    grant_role(@intake_trainer, Role::TRAINER)
    grant_role(@intake_trainer, Role::INTAKE)
    grant_role(@trainer, Role::TRAINER)
    grant_role(@intake_only, Role::INTAKE)
    grant_role(@art_trainer, Role::ART_TRAINER_BASE | Position::GREEN_DOT_TRAINING)
    grant_role(@art_trainer, Role::INTAKE)

    Current.person = @admin

    # The roster is read from status history, and person_status has no fixture
    # file -- without this the page is empty and every assertion below passes
    # vacuously.
    place_in_pipeline(@flagged, YEAR)
  end

  teardown do
    Current.reset
    Rails.cache.clear
    travel_back
  end

  # --- the two stacked gates -------------------------------------------------

  test "a trainer who also holds intake can view the pipeline" do
    sign_in_as(@intake_trainer)
    get training_unified_flagging_path("in-person")

    assert_response :success
    assert_match "#{YEAR} Unified Flagging", response.body
    assert_match @flagged.callsign, response.body
  end

  test "the training tree's own roles are not enough without intake" do
    sign_in_as(@trainer)
    get training_unified_flagging_path("in-person")

    assert_redirected_to me_root_path
    assert_equal DENY_MESSAGE, flash[:error]
  end

  test "intake alone is not enough without access to the training tree" do
    sign_in_as(@intake_only)
    get training_unified_flagging_path("in-person")

    assert_redirected_to me_root_path
    assert_match(/not authorized to view/, flash[:error])
  end

  test "the detail frame is behind the same two gates" do
    sign_in_as(@trainer)
    get training_unified_flagging_detail_path("in-person", @flagged)

    assert_redirected_to me_root_path
    assert_equal DENY_MESSAGE, flash[:error]
  end

  # --- In-Person only --------------------------------------------------------

  test "an ART slug is sent back to its own sessions instead of showing the pipeline" do
    sign_in_as(@art_trainer)
    get training_unified_flagging_path("green-dot")

    assert_redirected_to training_path("green-dot")
    assert_match(/In-Person Training/, flash[:error])
  end

  test "the ART sidebar does not offer unified flagging" do
    green_dot = Position.find(Position::GREEN_DOT_TRAINING)
    art_items = TrainingMenu.definition(green_dot)[:sections]
                            .flat_map { |section| section[:items] }
                            .map { |item| item[:title] }

    assert_not_includes art_items, "Unified Flagging"
    assert_includes TrainingMenu.definition(Position.find(Position::TRAINING))[:sections]
                                .flat_map { |section| section[:items] }
                                .map { |item| item[:title] },
                    "Unified Flagging"
  end

  # --- read-only (upstream's trainingNotesOnly) ------------------------------

  test "the detail frame offers no way to add a note even to an admin" do
    sign_in_as(@admin)
    get training_unified_flagging_detail_path("in-person", @flagged, year: YEAR)

    assert_response :success
    assert_no_match(/Add .* Note/, response.body)
    assert_no_match new_person_intake_note_path(@flagged), response.body
  end

  test "existing notes render, but without edit or delete controls" do
    sign_in_as(@admin)
    get training_unified_flagging_detail_path("in-person", @flagged, year: 2025)

    assert_response :success
    # The note itself must be on the page, or the two negatives below would
    # pass on an empty frame.
    assert_match "VC flagged a volunteer-coordination scheduling conflict", response.body
    assert_no_match edit_person_intake_note_path(@flagged, person_intake_note(:prospective_vc_note_2025)),
                    response.body
    assert_no_match(/turbo-method="delete"/, response.body)
  end

  test "the same admin on the same person does get every note control on the vc copy" do
    sign_in_as(@admin)
    get vc_unified_flagging_detail_path(@flagged, year: 2025)

    assert_response :success
    assert_match "VC flagged a volunteer-coordination scheduling conflict", response.body
    assert_match(/Add .* Note/, response.body)
    assert_match edit_person_intake_note_path(@flagged, person_intake_note(:prospective_vc_note_2025)),
                 response.body
    assert_match(/turbo-method="delete"/, response.body)
  end

  # --- the shared page still works under the training shell ------------------

  # Each line links to its own selection through this page's route, and the
  # pane it fills is read-only here: no Add-note button, whoever is viewing.
  test "selecting a name fills the pane through the training route, read-only" do
    sign_in_as(@admin)
    get training_unified_flagging_path("in-person")

    assert_response :success
    assert_select "li#person-#{@flagged.id} a[href=?]",
                  training_unified_flagging_path("in-person", year: YEAR, person: @flagged.id)

    get training_unified_flagging_path("in-person", person: @flagged.id)

    assert_response :success
    assert_match(/<turbo-frame[^>]*id="uf-pane"[^>]*target="_top"/, response.body)
    assert_select "aside", text: /No notes yet|Training/
    assert_no_match(/Add .* Note/, response.body)
    # Scoped to the pane: the navbar's own logout link is a Turbo delete too.
    assert_select "aside a", text: "Edit", count: 0
    assert_select "aside [data-turbo-method=delete]", count: 0
  end

  test "the detail frame renders bare, without the training shell around it" do
    sign_in_as(@admin)
    get training_unified_flagging_detail_path("in-person", @flagged, year: YEAR)

    assert_response :success
    assert_match(/<turbo-frame[^>]*id="uf-frame-#{@flagged.id}"[^>]*target="_top"/, response.body)
    assert_no_match "<html", response.body
  end

  test "the year selector re-scopes the list and the filters keep the year" do
    sign_in_as(@admin)
    place_in_pipeline(@flagged, 2025)
    get training_unified_flagging_path("in-person", year: 2025, training: "none")

    assert_response :success
    assert_match "2025 Unified Flagging", response.body
    # The filter-removal chip has to carry the year, or clearing a filter
    # bounces the page back to the current year.
    assert_match training_unified_flagging_path("in-person", year: 2025), response.body
  end

  test "search reaches the roster through the training route" do
    sign_in_as(@admin)

    get training_unified_flagging_path("in-person", q: @flagged.callsign)

    assert_response :success
    assert_match @flagged.callsign, response.body
    assert_match "Showing 1 of 1", response.body

    # The miss side is what discriminates: an unmatched roster member is the
    # only thing that tells a working filter from one that never ran. Asserting
    # the absence of someone the only_flagged roster excludes anyway would pass
    # with the search deleted.
    get training_unified_flagging_path("in-person", q: "nobodyisnamedthis")

    assert_response :success
    assert_no_match @flagged.callsign, response.body
    assert_match "matched those filters", response.body
  end

  test "the sidebar lights the unified flagging item" do
    sign_in_as(@admin)
    get training_unified_flagging_path("in-person")

    assert_response :success
    assert_select "a[href=?]", training_unified_flagging_path("in-person")
  end

  # The tiles narrow the list through this page's own route, year kept.
  test "the stat tiles link back into the training route" do
    sign_in_as(@intake_trainer)

    get training_unified_flagging_path("in-person", year: YEAR)

    assert_select "a[href=?]", training_unified_flagging_path("in-person", year: YEAR, section: "personnel")

    get training_unified_flagging_path("in-person", year: YEAR, section: "flagged")

    assert_response :success
    assert_match "Section: Rank 3/4 or Bonk", response.body
  end
end
