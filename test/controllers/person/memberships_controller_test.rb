# frozen_string_literal: true

require "test_helper"

# rubocop:disable Style/ClassAndModuleChildren

class Person::MembershipsControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper

  setup do
    Rails.cache.clear

    @target = person(:active_ranger)
    @admin = person(:auditor_ranger)
    @manager = person(:echelon_ranger)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::TRAINER, "Trainer")
    ensure_role(Role::TECH_NINJA, "Tech Ninja")

    grant_role(@admin, Role::ADMIN)
    grant_role(@manager, Role::TRAINER)

    TeamManager.find_or_create_by!(person_id: @manager.id, team_id: teams(:mentor_cadre).id)
    TeamManager.find_or_create_by!(person_id: @manager.id, team_id: teams(:green_dot_cadre).id)

    @general_position = build_position("General Support", new_user_eligible: true)
    @mentor_public = build_position("Mentor Public Access",
                                    team: teams(:mentor_cadre),
                                    new_user_eligible: true,
                                    team_category: Position::TEAM_CATEGORY_PUBLIC)
    @mentor_shared = build_position("Mentor Shared Duty",
                                    team: teams(:mentor_cadre),
                                    deselect_on_team_join: true,
                                    team_category: Position::TEAM_CATEGORY_ALL_MEMBERS)
    @green_dot_optional = build_position("Green Dot Guide",
                                         team: teams(:green_dot_cadre),
                                         team_category: Position::TEAM_CATEGORY_OPTIONAL)
  end

  teardown do
    Rails.cache.clear
  end

  test "admin edit shows general positions and current memberships" do
    sign_in_as(@admin)
    @general_position.roles << Role.find(Role::ADMIN)

    get edit_person_membership_path(@target)

    assert_response :success
    assert_select "h1, h2", text: /Manage Teams & Positions .* TestRanger/i
    assert_select "h3", text: /General Positions/i, count: 1
    assert_select "span", text: /General Support/
    assert_select "span", text: /All Accounts/
    assert_select "article#team-box-#{teams(:council_cadre).id}", text: /Council Cadre/
    assert_select "article#team-box-#{teams(:khaki_team).id}", text: /Khaki Delegation/
    # The permission list is a native <details> dropdown named for assistive tech.
    assert_select "details.dropdown > summary", text: /1 Permission/
    assert_select "ul[aria-label='Granted Permissions'] li", text: "Admin"
  end

  test "non-admin edit only shows manageable teams" do
    sign_in_as(@manager)

    get edit_person_membership_path(@target)

    assert_response :success
    assert_select "h3", text: /General Positions/i, count: 0
    assert_select "article#team-box-#{teams(:mentor_cadre).id}", text: /Mentor Cadre/
    assert_select "article#team-box-#{teams(:green_dot_cadre).id}", text: /Green Dot Cadre/
    assert_select "article#team-box-#{teams(:council_cadre).id}", count: 0
    assert_select "article#team-box-#{teams(:khaki_team).id}", count: 0
  end

  test "update only changes memberships and positions the user can manage" do
    sign_in_as(@manager)

    patch person_membership_path(@target), params: {
      person_membership_form: {
        team_ids: [teams(:mentor_cadre).id, teams(:green_dot_cadre).id],
        manager_ids: [teams(:green_dot_cadre).id],
        position_ids: [
          positions(:mentor_manager).id,
          @green_dot_optional.id,
          @general_position.id
        ]
      }
    }

    assert_redirected_to person_path(@target)
    assert PersonTeam.have_team(teams(:green_dot_cadre).id, @target.id)
    assert TeamManager.manager?(teams(:green_dot_cadre).id, @target.id)
    assert PersonPosition.have_position?(@target.id, @green_dot_optional.id)
    assert_not PersonPosition.have_position?(@target.id, @general_position.id)

    assert PersonTeam.have_team(teams(:council_cadre).id, @target.id)
    assert PersonTeam.have_team(teams(:khaki_team).id, @target.id)
    assert PersonPosition.have_position?(@target.id, positions(:council_manager).id)
    assert PersonPosition.have_position?(@target.id, positions(:khaki_supervisor).id)
  end

  # What the form sends with every box unchecked: each list's hidden blank.
  EVERYTHING_UNCHECKED = { person_membership_form: { team_ids: [""], manager_ids: [""], position_ids: [""] } }.freeze

  test "unchecking a person's last team and last position removes them" do
    sign_in_as(@admin)
    PersonTeam.where(person_id: @target.id).where.not(team_id: teams(:mentor_cadre).id).delete_all
    PersonPosition.where(person_id: @target.id).where.not(position_id: positions(:mentor_manager).id).delete_all

    patch person_membership_path(@target), params: EVERYTHING_UNCHECKED

    assert_redirected_to person_path(@target)
    assert_not PersonTeam.have_team(teams(:mentor_cadre).id, @target.id)
    assert_not PersonPosition.have_position?(@target.id, positions(:mentor_manager).id)
  end

  test "a team manager unchecking every box removes only what they manage" do
    sign_in_as(@manager)

    patch person_membership_path(@target), params: EVERYTHING_UNCHECKED

    assert_redirected_to person_path(@target)
    assert_not PersonTeam.have_team(teams(:mentor_cadre).id, @target.id)
    assert_not PersonPosition.have_position?(@target.id, positions(:mentor_manager).id)
    assert PersonTeam.have_team(teams(:council_cadre).id, @target.id)
    assert PersonPosition.have_position?(@target.id, positions(:council_manager).id)
  end

  test "a list the request leaves out is left alone" do
    sign_in_as(@admin)
    TeamManager.find_or_create_by!(person_id: @target.id, team_id: teams(:mentor_cadre).id)
    team_ids = PersonTeam.where(person_id: @target.id).pluck(:team_id).map(&:to_s)
    position_ids = PersonPosition.where(person_id: @target.id).pluck(:position_id).sort

    patch person_membership_path(@target), params: { person_membership_form: { team_ids: ["", *team_ids] } }

    assert_redirected_to person_path(@target)
    assert TeamManager.manager?(teams(:mentor_cadre).id, @target.id)
    assert_equal position_ids, PersonPosition.where(person_id: @target.id).pluck(:position_id).sort
  end

  test "a scope that is not a set of lists is refused rather than clearing anything" do
    sign_in_as(@admin)
    TeamManager.find_or_create_by!(person_id: @target.id, team_id: teams(:mentor_cadre).id)

    [{}, { person_membership_form: "x" }].each do |params|
      patch person_membership_path(@target), params: params

      assert_response :bad_request, params.inspect
    end
    assert TeamManager.manager?(teams(:mentor_cadre).id, @target.id)
  end

  # Dropped, the junk would read as "fewer ids" and clear what it stood in for.
  test "a list holding something that is not an id is refused rather than clearing anything" do
    sign_in_as(@manager)

    patch person_membership_path(@target),
          params: { person_membership_form: { team_ids: ["", "abc"], manager_ids: [""], position_ids: [""] } }

    assert_response :bad_request
    assert PersonTeam.have_team(teams(:mentor_cadre).id, @target.id)
    assert PersonPosition.have_position?(@target.id, positions(:mentor_manager).id)
  end

  private

  def build_position(title, **attributes)
    Position.create!(
      {
        title: title,
        active: true,
        awards_eligible: false,
        awards_auto_grant: false,
        awards_grants_service_year: false,
        count_hours: true
      }.merge(attributes)
    )
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

# rubocop:enable Style/ClassAndModuleChildren
