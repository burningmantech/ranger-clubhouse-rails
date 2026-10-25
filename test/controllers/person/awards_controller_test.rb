# frozen_string_literal: true

require "test_helper"

class Person::AwardsControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include ActiveSupport::Testing::TimeHelpers

  # The exact text the role gate denies with -- asserted so a denial can never be
  # mistaken for one of the several other reasons a write may redirect to the index.
  DENY_MESSAGE = "Admin or Award Management role required to grant service recognition awards."

  setup do
    travel_to Time.zone.local(2026, 4, 16, 12, 0, 0)
    Rails.cache.clear
    Current.reset

    # :active_ranger carries a fixture award of every type -- team (:khaki_2020),
    # position (:ood_2023) and special (:volunteer_2022).
    @target = person(:active_ranger)
    @admin = person(:auditor_ranger)
    @award_manager = person(:echelon_ranger)
    @viewer = person(:ranger_with_custom_gender)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::AWARD_MANAGEMENT, "Award Management")
    ensure_role(Role::EVENT_MANAGEMENT, "Event Management")
    ensure_role(Role::MENTOR, "Mentor")

    grant_role(@admin, Role::ADMIN)
    # AWARD_MANAGEMENT is not one of the roles PersonConcern admits to the person pages,
    # so the manager needs a viewing role on top of it to reach the controller at all.
    grant_role(@award_manager, Role::EVENT_MANAGEMENT)
    grant_role(@award_manager, Role::AWARD_MANAGEMENT)
    grant_role(@viewer, Role::MENTOR)

    Current.person = @admin
  end

  teardown do
    Current.reset
    travel_back
    Rails.cache.clear
  end

  # --- index -----------------------------------------------------------------

  test "index lists the person's awards split into team, position and special groups" do
    sign_in_as(@award_manager)

    get person_awards_path(@target)

    assert_response :success
    assert_select "body", text: /Service Recognition Awards — #{@target.callsign}/
    assert_select "body", text: /Khaki Delegation/           # team group
    assert_select "body", text: /OOD \(Officer of the Day\)/ # position group
    assert_select "body", text: /Volunteer Excellence/       # special group
  end

  test "manager sees the grant, edit and rebuild controls" do
    sign_in_as(@award_manager)

    get person_awards_path(@target)

    assert_response :success
    assert_select "a[href^=?]", new_person_award_path(@target), minimum: 1
    assert_select "a[href=?]", edit_person_award_path(@target, person_awards(:khaki_2020)), count: 1
    assert_includes response.body, rebuild_person_awards_path(@target)
  end

  # The read-only fallback: index is ungated, so anyone who may see the person sees the
  # awards -- they just get no way to change them.
  test "viewer without the role sees the awards but no management controls" do
    sign_in_as(@viewer)

    get person_awards_path(@target)

    assert_response :success
    assert_select "body", text: /Khaki Delegation/
    assert_select "a[href^=?]", new_person_award_path(@target), count: 0
    assert_select "a[href=?]", edit_person_award_path(@target, person_awards(:khaki_2020)), count: 0
    assert_not_includes response.body, rebuild_person_awards_path(@target)
  end

  # --- the role gate ---------------------------------------------------------

  test "every write action is denied without the award management role" do
    sign_in_as(@viewer)

    assert_no_difference -> { PersonAward.count } do
      write_requests.each do |action, request|
        request.call

        assert_redirected_to person_awards_path(@target), "#{action} should have been denied"
        assert_equal DENY_MESSAGE, flash[:error], "#{action} should say why it was denied"

        # An unfollowed redirect leaves its flash in the session, where the next action
        # would read it back and pass on a denial it never triggered. Consume it.
        follow_redirect!
      end
    end

    assert_equal "Khaki Delegation member 2020", person_awards(:khaki_2020).reload.notes
  end

  test "the award management role opens every write action" do
    assert_gate_open_for @award_manager
  end

  # RoleGate defaults to admin: true, so ADMIN clears the gate without holding
  # AWARD_MANAGEMENT.
  test "admin opens every write action" do
    assert_gate_open_for @admin
  end

  # --- new -------------------------------------------------------------------

  test "new renders the matching entity select for every award type" do
    sign_in_as(@award_manager)

    { "team" => "person_award[team_id]",
      "position" => "person_award[position_id]",
      "special" => "person_award[award_id]" }.each do |type, field|
      get new_person_award_path(@target, type: type)

      assert_response :success, "new should render for #{type}"
      assert_select "select[name=?]", field, { count: 1 }, "#{type} should offer its own entity select"
    end
  end

  # The type names which select to render, so an unrecognized one has no form to show.
  test "new rejects an unknown award type" do
    sign_in_as(@award_manager)

    get new_person_award_path(@target, type: "bogus")

    assert_redirected_to person_awards_path(@target)
    assert_equal "Unknown award type.", flash[:error]
  end

  # --- create ----------------------------------------------------------------

  test "manager grants a team award" do
    sign_in_as(@award_manager)
    team = teams(:operations_team)

    assert_difference -> { PersonAward.count }, 1 do
      post person_awards_path(@target, type: "team"), params: {
        person_award: award_params(team_id: team.id)
      }
    end

    assert_redirected_to person_awards_path(@target)
    granted = PersonAward.find_by!(person_id: @target.id, team_id: team.id, year: 2024)
    assert_equal @award_manager.id, granted.creator_person_id
    assert_nil granted.position_id
    assert_nil granted.award_id
  end

  test "manager grants a position award" do
    sign_in_as(@award_manager)
    position = positions(:mentor_lead)

    assert_difference -> { PersonAward.count }, 1 do
      post person_awards_path(@target, type: "position"), params: {
        person_award: award_params(position_id: position.id)
      }
    end

    assert_redirected_to person_awards_path(@target)
    granted = PersonAward.find_by!(person_id: @target.id, position_id: position.id, year: 2024)
    assert_equal @award_manager.id, granted.creator_person_id
    assert_nil granted.team_id
    assert_nil granted.award_id
  end

  test "manager grants a special service award" do
    sign_in_as(@award_manager)
    award = awards(:innovation_award)

    assert_difference -> { PersonAward.count }, 1 do
      post person_awards_path(@target, type: "special"), params: {
        person_award: award_params(award_id: award.id)
      }
    end

    assert_redirected_to person_awards_path(@target)
    granted = PersonAward.find_by!(person_id: @target.id, award_id: award.id, year: 2024)
    assert_equal @award_manager.id, granted.creator_person_id
    assert_nil granted.team_id
    assert_nil granted.position_id
  end

  # :khaki_2020 already gives the person this team for this year. The duplicate check
  # lives in a custom validation, so the form has to come back rather than 500.
  test "granting a duplicate award for a year re-renders the form" do
    sign_in_as(@award_manager)
    existing = person_awards(:khaki_2020)

    assert_no_difference -> { PersonAward.count } do
      post person_awards_path(@target, type: "team"), params: {
        person_award: award_params(team_id: existing.team_id, year: existing.year)
      }
    end

    assert_response :unprocessable_entity
  end

  # --- update / destroy ------------------------------------------------------

  test "manager updates an award" do
    sign_in_as(@award_manager)
    award = person_awards(:ood_2023)

    patch person_award_path(@target, award), params: {
      person_award: { year: 2024, awards_grants_service_year: "1", notes: "Corrected the year." }
    }

    assert_redirected_to person_awards_path(@target)
    award.reload
    assert_equal 2024, award.year
    assert award.awards_grants_service_year
    assert_equal "Corrected the year.", award.notes
  end

  test "manager deletes an award" do
    sign_in_as(@award_manager)
    award = person_awards(:volunteer_2022)

    assert_difference -> { PersonAward.count }, -1 do
      delete person_award_path(@target, award)
    end

    assert_redirected_to person_awards_path(@target)
    assert_not PersonAward.exists?(award.id)
  end

  # --- rebuild ---------------------------------------------------------------

  # AwardManagement.rebuild_for_person_id is a deliberate no-op -- its body is commented
  # out upstream -- so the button must report success and touch nothing.
  test "manager rebuilds awards without changing them" do
    sign_in_as(@award_manager)

    assert_no_difference -> { PersonAward.count } do
      post rebuild_person_awards_path(@target)
    end

    assert_redirected_to person_awards_path(@target)
    assert_equal "Awards rebuilt.", flash[:success]
  end

  private

  # Sensible params for a new award of any type; pass the entity id that names the type.
  def award_params(overrides = {})
    { year: 2024, awards_grants_service_year: "1", notes: "Granted in a test." }.merge(overrides)
  end

  # Every action behind the role gate, as a callable request -- so the gate can be
  # asserted over all six without six near-identical tests.
  def write_requests
    award = person_awards(:khaki_2020)

    {
      "new" => -> { get new_person_award_path(@target, type: "team") },
      "create" => -> {
        post person_awards_path(@target, type: "team"),
             params: { person_award: award_params(team_id: teams(:operations_team).id) }
      },
      "edit" => -> { get edit_person_award_path(@target, award) },
      "update" => -> { patch person_award_path(@target, award), params: { person_award: { notes: "Edited." } } },
      "destroy" => -> { delete person_award_path(@target, award) },
      "rebuild" => -> { post rebuild_person_awards_path(@target) }
    }
  end

  # Asserted by effect rather than by flash: a denial and a successful write both redirect
  # to the index, so only the outcome tells them apart.
  def assert_gate_open_for(person)
    sign_in_as(person)
    award = person_awards(:khaki_2020)

    get new_person_award_path(@target, type: "team")
    assert_response :success

    get edit_person_award_path(@target, award)
    assert_response :success

    assert_difference -> { PersonAward.count }, 1 do
      post person_awards_path(@target, type: "special"),
           params: { person_award: award_params(award_id: awards(:innovation_award).id) }
    end

    patch person_award_path(@target, award), params: { person_award: { notes: "Gate check." } }
    assert_equal "Gate check.", award.reload.notes

    assert_difference -> { PersonAward.count }, -1 do
      delete person_award_path(@target, award)
    end

    post rebuild_person_awards_path(@target)
    assert_equal "Awards rebuilt.", flash[:success]
  end

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
