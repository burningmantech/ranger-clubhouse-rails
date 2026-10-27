# frozen_string_literal: true

require "test_helper"

# The team side of resource documents: the tag and title a first document is
# filed under, and who may write a team's document at all.
class TeamTest < ActiveSupport::TestCase
  include TimesheetAdminTestHelper # ensure_role / grant_role

  setup do
    Current.reset

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::TECH_NINJA, "Tech Ninja")
    ensure_role(Role::EVENT_MANAGEMENT, "Event Management")
    ensure_role(Role::VEHICLE_INFO_UPDATE, "Vehicle Info Update")
    ensure_role(Role::TEAM_RESOURCE_MANAGEMENT, "Team Resource Doc Mgmt")

    @team = teams(:dirt_team)
    @other_team = teams(:operations_team)
  end

  teardown { Current.reset }

  # --- the tag and title (Laravel's buildResourceTag / buildResourceTitle) ----

  test "a title that names its type is filed under the title alone" do
    assert_equal "dirt-team-info", @team.build_resource_tag
    assert_equal "DIRT Team Document", @team.build_resource_title
  end

  test "a title that does not name its type gets the type added" do
    council = Team.new(title: "Council", type: Team::TYPE_CADRE)

    assert_equal "council-cadre-info", council.build_resource_tag
    assert_equal "Council Cadre Document", council.build_resource_title
  end

  # Upstream's Str::kebab keeps the dot ("volunteer-coords.-cadre-info").
  test "punctuation is dropped from the tag" do
    assert_equal "volunteer-coords-cadre-info",
                 Team.new(title: "Volunteer Coords. Cadre", type: Team::TYPE_CADRE).build_resource_tag
  end

  # --- who may write a team's document ----------------------------------------

  test "an admin with Event Management may write every team's document" do
    admin = person(:active_ranger)
    grant_role(admin, Role::ADMIN)
    grant_role(admin, Role::EVENT_MANAGEMENT)

    assert Team.resource_manageable_by?(admin)
    assert_equal Team.count, Team.resource_manageable_by(admin).count
  end

  # Upstream's page sat in the Ember ops area, whose route wanted Event
  # Management or Vehicle Info Update of everyone, Admins included.
  test "an admin without Event Management or Vehicle Info Update writes nothing" do
    admin = person(:active_ranger)
    grant_role(admin, Role::ADMIN)

    assert_not Team.resource_manageable_by?(admin)
    assert_empty Team.resource_manageable_by(admin)
  end

  test "a manager holding the role may write only the teams they manage" do
    manager = manager_of(@team, Role::EVENT_MANAGEMENT, Role::TEAM_RESOURCE_MANAGEMENT)

    assert Team.resource_manageable_by?(manager)
    assert_equal [@team.id], Team.resource_manageable_by(manager).pluck(:id)
  end

  test "Vehicle Info Update opens the page as Event Management does" do
    manager = manager_of(@team, Role::VEHICLE_INFO_UPDATE, Role::TEAM_RESOURCE_MANAGEMENT)

    assert Team.resource_manageable_by?(manager)
    assert_equal [@team.id], Team.resource_manageable_by(manager).pluck(:id)
  end

  test "the role and a team to manage, without Event Management, write nothing" do
    manager = manager_of(@team, Role::TEAM_RESOURCE_MANAGEMENT)

    assert_not Team.resource_manageable_by?(manager)
    assert_empty Team.resource_manageable_by(manager)
  end

  test "managing a team without the role writes nothing" do
    manager = manager_of(@team, Role::EVENT_MANAGEMENT)

    assert_not Team.resource_manageable_by?(manager)
    assert_empty Team.resource_manageable_by(manager)
  end

  test "the role without a team to manage writes nothing" do
    holder = person(:inactive_ranger)
    grant_role(holder, Role::EVENT_MANAGEMENT)
    grant_role(holder, Role::TEAM_RESOURCE_MANAGEMENT)

    assert_not Team.resource_manageable_by?(holder)
    assert_empty Team.resource_manageable_by(holder)
  end

  # The roster rule opens every team to a Tech Ninja; this one opens every team
  # to Admin alone. The ninja holds everything else a manager needs, so only the
  # every-team branch could hand them the other team.
  test "a tech ninja reaches only the teams they manage" do
    ninja = manager_of(@team, Role::TECH_NINJA, Role::EVENT_MANAGEMENT, Role::TEAM_RESOURCE_MANAGEMENT)

    assert Team.resource_manageable_by?(ninja)
    assert_equal [@team.id], Team.resource_manageable_by(ninja).pluck(:id)
  end

  test "no one signed in writes nothing" do
    assert_not Team.resource_manageable_by?(nil)
    assert_empty Team.resource_manageable_by(nil)
  end

  private

  def manager_of(team, *roles)
    manager = person(:retired_ranger)
    roles.each { |role| grant_role(manager, role) }
    TeamManager.create!(team_id: team.id, person_id: manager.id)
    manager
  end
end
