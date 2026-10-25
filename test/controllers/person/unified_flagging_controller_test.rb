# frozen_string_literal: true

require "test_helper"

class Person::UnifiedFlaggingControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include ActiveSupport::Testing::TimeHelpers

  # The controller narrows PersonConcern's broad gate with its own authorize_role
  # (class_attribute last-wins) -- this is that narrowed message, not PersonConcern's.
  DENY_MESSAGE = "Admin, Intake, or Regional Management role required to view intake records."

  setup do
    travel_to Time.zone.local(2026, 4, 16, 12, 0, 0)
    Rails.cache.clear
    Current.reset

    @target = person(:prospective_ranger)

    @admin = person(:auditor_ranger)
    # Holds INTAKE *and* VC, so it also exercises the "VC-with-page-access" branch
    # of can_edit_known_folds's has_role?([ADMIN, VC, INTAKE]) check.
    @intake_and_vc = person(:echelon_ranger)
    @regional_only = person(:ranger_with_custom_gender)
    # Holds a role in PersonConcern's broad gate (MENTOR) but not in this
    # controller's narrowed [ADMIN, INTAKE, REGIONAL_MANAGEMENT] gate.
    @role_less_viewer = person(:inactive_ranger)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::INTAKE, "Intake")
    ensure_role(Role::REGIONAL_MANAGEMENT, "Regional Management")
    ensure_role(Role::VC, "Volunteer Coordinator")
    ensure_role(Role::MENTOR, "Mentor")

    grant_role(@admin, Role::ADMIN)
    grant_role(@intake_and_vc, Role::INTAKE)
    grant_role(@intake_and_vc, Role::VC)
    grant_role(@regional_only, Role::REGIONAL_MANAGEMENT)
    grant_role(@role_less_viewer, Role::MENTOR)

    Current.person = @admin
  end

  teardown do
    Current.reset
    travel_back
    Rails.cache.clear
  end

  # --- show: role gate ---------------------------------------------------

  test "show denies a viewer without admin, intake, or regional management" do
    sign_in_as(@role_less_viewer)

    get person_unified_flagging_path(@target)

    assert_redirected_to me_root_path
    assert_equal DENY_MESSAGE, flash[:error]
  end

  # --- show: full view ----------------------------------------------------

  test "admin sees the full view: all four teams, training history, and the known-folks form" do
    sign_in_as(@admin)

    get person_unified_flagging_path(@target)

    assert_response :success
    %w[Personnel RRN VC Mentors].each do |label|
      assert_select "body", text: /#{label}/, minimum: 1
    end
    assert_select "body", text: /Training & Alpha Shift History/
    assert_select "body", text: /Known Rangers & Applicants/
    assert_select "form[action=?]", person_unified_flagging_known_folks_path(@target)
    assert_select "input[name=?]", "person[known_rangers]"
    assert_select "input[name=?]", "person[known_pnvs]"
  end

  # Regression: TableHelper#row_header dropped non-String values, so the numeric
  # year rendered as an empty <th>. prospective_ranger's fixtures put 2024 (mentor
  # pass), 2025 (Alpha) and 2026 (personnel flag) into pnv_history.
  test "the Training & Alpha Shift History table renders the year in each row header" do
    sign_in_as(@admin)

    get person_unified_flagging_path(@target)

    assert_response :success
    assert_select "th[scope=row]", text: /2024/, minimum: 1
    assert_select "th[scope=row]", text: /2026/, minimum: 1
  end

  # The Training note group is read-only (TraineeNote, not PersonIntakeNote) and
  # renders regardless of write permissions.
  test "the read-only Training note group renders a session's trainee notes" do
    sign_in_as(@admin)

    Position.find_or_initialize_by(id: Position::TRAINING)
            .update!(title: "In-Person Training", type: Position::TYPE_TRAINING, active: true)
    slot = Slot.create!(position_id: Position::TRAINING,
                        begins: Time.zone.local(2025, 6, 1, 9, 0, 0),
                        ends: Time.zone.local(2025, 6, 1, 17, 0, 0),
                        max: 10, active: true, timezone: "America/Los_Angeles")
    PersonSlot.create!(person_id: @target.id, slot_id: slot.id)
    TraineeStatus.create!(person_id: @target.id, slot_id: slot.id, status: TraineeStatus::STATUS_PASSED, feedback_delivered: true)
    TraineeNote.create!(person_id: @target.id, slot_id: slot.id,
                        note: "Handled the radio call well.", person_source_id: @admin.id)

    get person_unified_flagging_path(@target)

    assert_response :success
    assert_select "body", text: /Handled the radio call well\./
    assert_select "body", text: /training passed/
    assert_select "body", text: /Lead trainer delivered feedback/
  end

  test "intake (also holding vc) sees the full view and the known-folks form" do
    sign_in_as(@intake_and_vc)

    get person_unified_flagging_path(@target)

    assert_response :success
    %w[Personnel RRN VC Mentors].each do |label|
      assert_select "body", text: /#{label}/, minimum: 1
    end
    assert_select "body", text: /Training & Alpha Shift History/
    assert_select "form[action=?]", person_unified_flagging_known_folks_path(@target)
  end

  # --- show: empty states -------------------------------------------------

  # alpha_ranger has no rank, note or training history in the fixtures. Only a
  # team the viewer can't write draws the empty state -- this viewer writes VC
  # alone -- so an admin would never see these lines. Labels come from the
  # helper constant, as the view's do, so relabelling a team is not a failure.
  test "a person with no history shows the empty teams and history to a viewer who can't write them" do
    sign_in_as(@intake_and_vc)

    get person_unified_flagging_path(person(:alpha_ranger))

    assert_response :success
    %w[personnel rrn mentor].each do |team|
      assert_select ".empty-state", text: "No #{IntakeHelper::TEAM_META.fetch(team)[:label]} notes."
    end
    assert_select ".empty-state", text: "No training or Alpha shift information available."
  end

  # --- show: RRN-restricted view ------------------------------------------

  test "regional-management-only viewer sees only the RRN team, no training/known-folks/other teams" do
    sign_in_as(@regional_only)

    get person_unified_flagging_path(@target)

    assert_response :success
    assert_select "body", text: /RRN/, minimum: 1
    assert_select "body", text: /Regional Ranger Network/

    %w[Personnel Mentors].each do |label|
      assert_select "body", text: /#{label}/, count: 0
    end
    assert_select "body", text: /Training & Alpha Shift History/, count: 0
    assert_select "body", text: /Known Rangers & Applicants/, count: 0
    assert_select "form[action=?]", person_unified_flagging_known_folks_path(@target), count: 0
    assert_select "input[name=?]", "person[known_rangers]", count: 0
  end

  # --- show: personnel danger banner --------------------------------------

  test "personnel danger banner renders when personnel_rank is 4 for the current year" do
    sign_in_as(@admin)

    get person_unified_flagging_path(@target)

    assert_response :success
    assert_select "body", text: /Personnel Flag Raised for #{@target.callsign}/
  end

  test "personnel danger banner does not render when the FLAG year is not the current year" do
    sign_in_as(@admin)

    # prospective_ranger_2026's personnel_rank: 4 fixture row falls outside the
    # <= year window and personnel_issue only flags r.year == Current.year, so
    # viewing from an earlier "current year" must not show the banner.
    travel_to Time.zone.local(2024, 4, 16, 12, 0, 0) do
      get person_unified_flagging_path(@target)

      assert_response :success
      assert_select "body", text: /Personnel Flag Raised/, count: 0
    end
  end

  # --- update_known_folks ---------------------------------------------------

  test "admin can update known rangers and pnvs" do
    sign_in_as(@admin)

    patch person_unified_flagging_known_folks_path(@target), params: {
      person: { known_rangers: "Alice, Bob", known_pnvs: "Carol" }
    }

    assert_redirected_to person_unified_flagging_path(@target)
    assert_equal "Known Rangers/PNVs updated.", flash[:success]
    @target.reload
    assert_equal "Alice, Bob", @target.known_rangers
    assert_equal "Carol", @target.known_pnvs
  end

  test "intake (also holding vc) can update known rangers and pnvs" do
    sign_in_as(@intake_and_vc)

    patch person_unified_flagging_known_folks_path(@target), params: {
      person: { known_rangers: "Dave", known_pnvs: "Erin" }
    }

    assert_redirected_to person_unified_flagging_path(@target)
    @target.reload
    assert_equal "Dave", @target.known_rangers
    assert_equal "Erin", @target.known_pnvs
  end

  test "a mentor-only viewer is denied at the page-level gate before reaching known-folks update" do
    sign_in_as(@role_less_viewer)

    patch person_unified_flagging_known_folks_path(@target), params: {
      person: { known_rangers: "Should not persist" }
    }

    assert_redirected_to me_root_path
    assert_equal DENY_MESSAGE, flash[:error]
    assert_not_equal "Should not persist", @target.reload.known_rangers
  end

  test "a regional-management-only viewer can view the page but is denied updating known folks" do
    sign_in_as(@regional_only)

    patch person_unified_flagging_known_folks_path(@target), params: {
      person: { known_rangers: "Should not persist" }
    }

    assert_redirected_to person_unified_flagging_path(@target)
    assert_equal "Not authorized", flash[:error]
    assert_not_equal "Should not persist", @target.reload.known_rangers
  end

  # The badge reads the stored verdict of a session that has ended: a no-show
  # says so, and anything else short of a pass reads "training not passed".
  test "an ended training session is badged by its verdict" do
    sign_in_as(@admin)

    position = Position.find_or_initialize_by(id: Position::TRAINING)
    position.assign_attributes(title: "In-Person Training", type: Position::TYPE_TRAINING, active: true)
    position.save!

    slot = Slot.create!(position_id: Position::TRAINING, begins: Time.zone.local(2026, 3, 1, 9, 0, 0),
                        ends: Time.zone.local(2026, 3, 1, 17, 0, 0), max: 10, active: true,
                        timezone: "America/Los_Angeles")
    PersonSlot.create!(person_id: @target.id, slot_id: slot.id)
    row = TraineeStatus.create!(person_id: @target.id, slot_id: slot.id,
                                status: TraineeStatus::STATUS_NOT_PASSED, rank: 3)

    get person_unified_flagging_path(@target)

    assert_response :success
    assert_match "training not passed", response.body

    row.update!(status: TraineeStatus::STATUS_NO_SHOW)
    get person_unified_flagging_path(@target)

    assert_match "training no-show", response.body
  end

  private

  def ensure_role(id, title)
    role = Role.find_or_initialize_by(id: id)
    role.title = title
    role.new_user_eligible = false
    role.save!
  end

  def grant_role(person, role_id)
    PersonRole.find_or_create_by!(person_id: person.id, role_id: role_id)
    RoleManager.purge_person(person.id.to_s)
  end
end
