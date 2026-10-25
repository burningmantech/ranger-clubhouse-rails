# frozen_string_literal: true

require "test_helper"

class TeamsPositions::RosterManagementControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include DomIdTestHelper

  setup do
    Rails.cache.clear
    Current.reset

    @admin = person(:active_ranger)
    @tech_ninja = person(:echelon_ranger)
    @manager = person(:retired_ranger)
    @outsider = person(:inactive_ranger)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::TECH_NINJA, "Tech Ninja")
    ensure_role(Role::EVENT_MANAGEMENT, "Event Management")
    grant_role(@admin, Role::ADMIN)
    grant_role(@tech_ninja, Role::TECH_NINJA)
    # A team_manager row alone no longer opens the page: the manager needs
    # Event Management (or Admin) as well.
    grant_role(@manager, Role::EVENT_MANAGEMENT)

    @team = teams(:dirt_team)
    @other_team = teams(:operations_team)
    TeamManager.create!(team_id: @team.id, person_id: @manager.id)

    # No fixture position carries a team_category, and the grid is built out of
    # it -- see the report test for the same setup.
    @recommended = create_position("Dirt Patrol", Position::TEAM_CATEGORY_ALL_MEMBERS)
    @optional = create_position("Dirt Lead", Position::TEAM_CATEGORY_OPTIONAL)
    @public = create_position("Dirt Training", Position::TEAM_CATEGORY_PUBLIC)

    @idle = person(:prospective_ranger)      # granted everything, never rangered
    @veteran = person(:auditor_ranger)       # rangered a recommended position

    [@idle, @veteran].each do |member|
      PersonTeam.create!(team_id: @team.id, person_id: member.id)
      [@recommended, @optional, @public].each do |position|
        PersonPosition.create!(person_id: member.id, position_id: position.id)
      end
    end
    add_timesheet(@veteran, @recommended, 2025)

    sign_in_as(@admin)
  end

  teardown do
    Current.reset
    Rails.cache.clear
  end

  # ---------------------------------------------------------------- access

  test "an admin reaches the index" do
    get teams_positions_roster_management_path

    assert_response :success
    assert_select "h1", /Roster Management/
  end

  test "a tech ninja reaches a roster" do
    sign_in_as(@tech_ninja)
    get teams_positions_roster_management_team_path(@team)

    assert_response :success
  end

  test "a team manager reaches their own team's roster" do
    sign_in_as(@manager)
    get teams_positions_roster_management_team_path(@team)

    assert_response :success
    assert_select "h1", /#{@team.title}/
  end

  # The gate is per team, not per role: managing one team must not open another.
  test "a team manager is refused a team they do not manage" do
    sign_in_as(@manager)
    get teams_positions_roster_management_team_path(@other_team)

    assert_redirected_to me_root_path
    assert_match(/not available to you/i, flash[:error])
    assert_no_match(/#{@other_team.title}/, flash[:error].to_s,
                    "the refusal must not name a team the reader cannot reach")
  end

  # Managing a team is not by itself enough -- the page hands out and takes
  # away position grants for a whole roster at once.
  test "a team manager without Event Management or Admin is refused" do
    bare = person(:alpha_ranger)
    TeamManager.create!(team_id: @team.id, person_id: bare.id)
    sign_in_as(bare)

    get teams_positions_roster_management_team_path(@team)

    assert_redirected_to me_root_path
    assert_match(/event management or admin/i, flash[:error])
  end

  # ...and the role is not by itself enough either: it opens the page, the
  # team_manager row decides which rosters.
  test "an Event Management person who manages no team is refused" do
    em = person(:alpha_ranger)
    grant_role(em, Role::EVENT_MANAGEMENT)
    sign_in_as(em)

    get teams_positions_roster_management_path

    assert_redirected_to me_root_path
  end

  test "an Event Management person sees only the teams they manage" do
    sign_in_as(@manager)
    get teams_positions_roster_management_path

    assert_response :success
    assert_select "a", text: /#{@team.title}/
    assert_select "a", text: /#{@other_team.title}/, count: 0
  end

  test "someone who manages no team is refused the index" do
    sign_in_as(@outsider)
    get teams_positions_roster_management_path

    assert_redirected_to me_root_path
  end

  test "someone who manages no team is refused a roster" do
    sign_in_as(@outsider)
    get teams_positions_roster_management_team_path(@team)

    assert_redirected_to me_root_path
  end

  test "a team manager cannot revoke on a team they do not manage" do
    sign_in_as(@manager)
    assert_no_difference -> { PersonTeam.count } do
      post teams_positions_roster_management_apply_path(@other_team), params: remove_params([@idle])
    end

    assert_redirected_to me_root_path
  end

  test "the index lists only the teams a manager manages" do
    sign_in_as(@manager)
    get teams_positions_roster_management_path

    assert_select "a", text: /#{@team.title}/
    assert_select "a", text: /#{@other_team.title}/, count: 0
  end

  # ---------------------------------------------------------------- roster

  test "the roster draws a column for every position and a row for every person" do
    get teams_positions_roster_management_team_path(@team)

    assert_response :success
    assert_select "th", text: @recommended.title
    assert_select "th", text: @optional.title
    assert_select "th", text: @public.title
    assert_select "tbody tr", 2
    assert_unique_dom_ids
  end

  test "the roster explains what NS and a dash mean" do
    get teams_positions_roster_management_team_path(@team)

    assert_select "body", /never used/
    assert_select "body", /not granted/
  end

  # A reader of this page can lack the roles the person pages need: Tech Ninja
  # opens every roster but is not in PersonConcern::VIEW_ROLES, so a linked
  # callsign would bounce them to /me. (Event Management is in that list, which
  # is why the manager sees links.)
  test "callsigns are plain text for a reader who cannot open person pages" do
    sign_in_as(@tech_ninja)
    get teams_positions_roster_management_team_path(@team)

    assert_select "a[href=?]", person_path(@idle.id), count: 0
    assert_select "body", /#{@idle.callsign}/
  end

  test "callsigns link to the person page for a reader who can open one" do
    get teams_positions_roster_management_team_path(@team)

    assert_select "a[href=?]", person_path(@idle.id)
  end

  # ---------------------------------------------------------------- filters

  test "the never-rangered-recommended view keeps only people with no recommended year" do
    get teams_positions_roster_management_team_path(@team),
        params: { view: TeamsPositions::RosterManagementHelper::VIEW_NEVER_RECOMMENDED }

    assert_select "tbody tr", 1
    assert_select "tbody", /#{@idle.callsign}/
    assert_select "tbody", { text: /#{@veteran.callsign}/, count: 0 }
  end

  test "the never-rangered-optional view keeps someone who rangered only a recommended position" do
    get teams_positions_roster_management_team_path(@team),
        params: { view: TeamsPositions::RosterManagementHelper::VIEW_NEVER_OPTIONAL }

    assert_select "tbody tr", 2
  end

  test "the combined never view keeps only people idle in both categories" do
    get teams_positions_roster_management_team_path(@team),
        params: { view: TeamsPositions::RosterManagementHelper::VIEW_NEVER_ALL }

    assert_select "tbody tr", 1
  end

  test "the callsign filter narrows the roster" do
    get teams_positions_roster_management_team_path(@team), params: { callsign: @veteran.callsign }

    assert_select "tbody tr", 1
    assert_select "tbody", /#{@veteran.callsign}/
  end

  # A hand-edited view has to fall back to everyone, not to an empty grid that
  # looks like the team lost its roster.
  test "an unknown view falls back to showing everyone" do
    get teams_positions_roster_management_team_path(@team), params: { view: "no-such-view" }

    assert_select "tbody tr", 2
  end

  # The stat boxes describe the team; only the filter bar's count follows the
  # filter. Narrowing both would leave no way to see the team's real size.
  test "the stat boxes stay team-wide while the count follows the filter" do
    get teams_positions_roster_management_team_path(@team),
        params: { view: TeamsPositions::RosterManagementHelper::VIEW_NEVER_ALL }

    assert_select "body", /Showing 1 of 2 people/
    assert_select "body", /2\s*People/m
  end

  # ---------------------------------------------------------------- revoke

  test "revoking removes the membership and the recommended and optional grants" do
    post teams_positions_roster_management_apply_path(@team), params: remove_params([@idle])

    assert_redirected_to teams_positions_roster_management_team_path(@team)
    assert_not PersonTeam.exists?(team_id: @team.id, person_id: @idle.id)
    assert_not PersonPosition.exists?(person_id: @idle.id, position_id: @recommended.id)
    assert_not PersonPosition.exists?(person_id: @idle.id, position_id: @optional.id)
  end

  test "revoking leaves a granted public position alone" do
    post teams_positions_roster_management_apply_path(@team), params: remove_params([@idle])

    assert PersonPosition.exists?(person_id: @idle.id, position_id: @public.id)
  end

  test "revoking logs the removal against the person" do
    post teams_positions_roster_management_apply_path(@team), params: remove_params([@idle])

    assert ActionLog.exists?(target_person_id: @idle.id, event: "person-team-remove")
    assert ActionLog.exists?(target_person_id: @idle.id, event: "person-position-remove")
  end

  # PersonTeamLog.remove_person closes the open membership row rather than
  # writing a new one, so the history keeps when the person joined.
  test "revoking closes the open membership history row" do
    log = PersonTeamLog.create!(team_id: @team.id, person_id: @idle.id, joined_on: 1.year.ago)

    post teams_positions_roster_management_apply_path(@team), params: remove_params([@idle])

    assert_not_nil log.reload.left_on
  end

  test "a batch revoke removes everyone selected" do
    post teams_positions_roster_management_apply_path(@team),
         params: remove_params([@idle, @veteran])

    assert_equal 0, PersonTeam.where(team_id: @team.id).count
    assert_match(/#{@idle.callsign}/, flash[:success])
    assert_match(/#{@veteran.callsign}/, flash[:success])
  end

  test "revoking with nothing selected says so and changes nothing" do
    assert_no_difference -> { PersonTeam.count } do
      post teams_positions_roster_management_apply_path(@team), params: remove_params([])
    end

    assert_match(/no one was selected/i, flash[:error])
  end

  test "the filter in force is carried back to the roster" do
    view = TeamsPositions::RosterManagementHelper::VIEW_NEVER_ALL
    post teams_positions_roster_management_apply_path(@team),
         params: remove_params([@idle]).merge(view:)

    assert_redirected_to teams_positions_roster_management_team_path(@team, view:)
  end

  # The API issues the position revoke and the team removal as two separate
  # requests, and says so: a failure between them strands the person off the
  # team with their positions revoked, or on it with them gone. One transaction
  # is the whole reason this action exists server-side.
  test "a failure part way through leaves the person exactly as they were" do
    original = PersonTeam.method(:remove_person)
    PersonTeam.define_singleton_method(:remove_person) { |*| raise ActiveRecord::StatementInvalid, "boom" }

    post teams_positions_roster_management_apply_path(@team), params: remove_params([@idle])

    assert PersonTeam.exists?(team_id: @team.id, person_id: @idle.id)
    assert PersonPosition.exists?(person_id: @idle.id, position_id: @recommended.id),
           "the position revoke must roll back with the team removal"
    assert_match(/#{@idle.callsign}/, flash[:error])
  ensure
    PersonTeam.define_singleton_method(:remove_person, original)
  end

  # One person failing must not abandon the rest of the batch.
  test "a batch carries on past a failure and names the callsign that failed" do
    # The batch is processed in callsign order, so the FAILING person has to
    # sort first ("AuditorTest" before "ProspectiveNewbie") -- otherwise there
    # is nothing after the failure and the test proves nothing.
    failing_id = @veteran.id
    original = PersonTeam.method(:remove_person)
    PersonTeam.define_singleton_method(:remove_person) do |team_id, person_id, reason|
      raise ActiveRecord::StatementInvalid, "boom" if person_id == failing_id

      original.call(team_id, person_id, reason)
    end

    post teams_positions_roster_management_apply_path(@team),
         params: remove_params([@idle, @veteran])

    assert PersonTeam.exists?(team_id: @team.id, person_id: @veteran.id),
           "the failing person keeps their membership"
    assert_not PersonTeam.exists?(team_id: @team.id, person_id: @idle.id),
               "the batch must carry on past the failure and remove the rest"
    assert_match(/#{@veteran.callsign}/, flash[:error], "the failure names the callsign to retry")
    assert_match(/#{@idle.callsign}/, flash[:error], "and says who did get removed")
  ensure
    PersonTeam.define_singleton_method(:remove_person, original)
  end

  # A hand-posted id for someone with no tie to the team must change nothing --
  # and must not be reported as removed, which would put a person-team-remove
  # entry in their log for a membership they never had.
  test "a person id that is not on the roster is ignored" do
    stranger = person(:bonked_ranger)

    assert_no_difference -> { ActionLog.where(target_person_id: stranger.id).count } do
      post teams_positions_roster_management_apply_path(@team), params: remove_params([stranger])
    end

    assert_no_match(/#{stranger.callsign}/, flash.to_hash.values.join(" "))
    assert_match(/no one was selected/i, flash[:error])
  end

  # to_i read "#{id}x" as the id and removed that person from the team.
  test "person ids that are not ids select no one" do
    assert_no_difference -> { PersonTeam.count } do
      post teams_positions_roster_management_apply_path(@team),
           params: { action_type: RosterAction::REMOVE_FROM_TEAM, person_ids: ["", "abc", "#{@idle.id}x"] }
    end

    assert_match(/no one was selected/i, flash[:error])
  end

  # ------------------------------------------------------- guarded roles

  # The API applies Role::assertActorMayConfer to removal as well as granting
  # (PersonTeam::removePerson). Membership of a role-bearing team IS the role
  # grant, so revoking it takes the role away -- and PersonTeam.add_person
  # already refuses to hand out a role the actor does not hold. Without this a
  # plain manager of an Admin-granting team could strip Admin from its whole
  # roster in one post and could not put it back.
  test "a manager cannot revoke on a team that grants a role they do not hold" do
    TeamRole.create!(team_id: @team.id, role_id: Role::ADMIN)
    sign_in_as(@manager)

    assert_no_difference -> { PersonTeam.count } do
      post teams_positions_roster_management_apply_path(@team), params: remove_params([@idle])
    end

    assert_match(/do not hold it yourself/i, flash[:error])
  end

  test "an admin may revoke on a team that grants Admin" do
    TeamRole.create!(team_id: @team.id, role_id: Role::ADMIN)

    post teams_positions_roster_management_apply_path(@team), params: remove_params([@idle])

    assert_not PersonTeam.exists?(team_id: @team.id, person_id: @idle.id)
  end

  test "the roster says why it is read-only and disables the button" do
    TeamRole.create!(team_id: @team.id, role_id: Role::ADMIN)
    sign_in_as(@manager)

    get teams_positions_roster_management_team_path(@team)

    assert_select "body", /read-only for you/i
    assert_select "button[disabled]"
  end

  # A position grant carries roles too, so the same rule has to cover the
  # positions the revoke would strip, not only the team itself.
  test "a manager cannot revoke when a revocable position grants a role they lack" do
    PositionRole.create!(position_id: @optional.id, role_id: Role::TECH_NINJA)
    sign_in_as(@manager)

    assert_no_difference -> { PersonPosition.count } do
      post teams_positions_roster_management_apply_path(@team), params: remove_params([@idle])
    end

    assert_match(/do not hold it yourself/i, flash[:error])
  end

  # Team and position grants feed the cached role set. Without an explicit
  # purge the person keeps every role the team gave them on every later
  # request -- the cache has no expiry.
  test "revoking purges the person's cached role set" do
    purged = []
    original = RoleManager.method(:purge_person)
    RoleManager.define_singleton_method(:purge_person) do |person_id|
      purged << person_id
      original.call(person_id)
    end

    post teams_positions_roster_management_apply_path(@team), params: remove_params([@idle])

    assert_includes purged, @idle.id
  ensure
    RoleManager.define_singleton_method(:purge_person, original)
  end

  # A filter over a category the team has no positions in cannot narrow
  # anything -- it would draw a chip and return the whole roster.
  test "a view is not offered when the team has no positions in its category" do
    Position.where(id: @optional.id).update_all(team_category: Position::TEAM_CATEGORY_ALL_MEMBERS)

    get teams_positions_roster_management_team_path(@team)

    assert_select "option[value=?]", TeamsPositions::RosterManagementHelper::VIEW_NEVER_OPTIONAL,
                  count: 0
    assert_select "option[value=?]", TeamsPositions::RosterManagementHelper::VIEW_NEVER_RECOMMENDED
  end

  # ----------------------------------------------------------- grid cells

  test "a granted position renders its year and a never-used one renders NS" do
    get teams_positions_roster_management_team_path(@team)

    assert_select "tr#roster-person-#{@veteran.id}" do
      assert_select "td", text: /2025/
    end
    assert_select "tr#roster-person-#{@idle.id}" do
      assert_select ".badge", text: /NS/
    end
  end

  test "an ungranted position renders a dash with screen-reader text" do
    PersonPosition.where(person_id: @idle.id, position_id: @optional.id).delete_all

    get teams_positions_roster_management_team_path(@team)

    assert_select "tr#roster-person-#{@idle.id} .sr-only", text: "Not granted"
  end

  # ------------------------------------------------------- added filters

  test "the position filter finds the people who hold a position" do
    PersonPosition.where(person_id: @idle.id, position_id: @optional.id).delete_all

    get teams_positions_roster_management_team_path(@team), params: { position: "has-#{@optional.id}" }

    assert_select "tbody tr", 1
    assert_select "tbody", /#{@veteran.callsign}/
  end

  test "the position filter finds the people who do not hold a position" do
    PersonPosition.where(person_id: @idle.id, position_id: @optional.id).delete_all

    get teams_positions_roster_management_team_path(@team), params: { position: "lacks-#{@optional.id}" }

    assert_select "tbody tr", 1
    assert_select "tbody", /#{@idle.callsign}/
  end

  test "the last-activity filter finds the people with no activity at all" do
    get teams_positions_roster_management_team_path(@team),
        params: { year: TeamsPositions::RosterManagementHelper::YEAR_NEVER }

    assert_select "tbody tr", 1
    assert_select "tbody", /#{@idle.callsign}/
  end

  test "the last-activity filter finds the people whose last year was the one chosen" do
    get teams_positions_roster_management_team_path(@team), params: { year: "2025" }

    assert_select "tbody tr", 1
    assert_select "tbody", /#{@veteran.callsign}/
  end

  test "a year no one was last active in is not offered" do
    get teams_positions_roster_management_team_path(@team)

    assert_select "option[value=?]", "2025"
    assert_select "option[value=?]", "2019", count: 0
  end

  test "the status filter narrows the roster" do
    get teams_positions_roster_management_team_path(@team), params: { status: @veteran.status }

    assert_select "tbody tr", 1
    assert_select "tbody", /#{@veteran.callsign}/
  end

  test "filters combine rather than replace each other" do
    get teams_positions_roster_management_team_path(@team),
        params: { position: "has-#{@optional.id}", status: @idle.status }

    assert_select "tbody tr", 1
    assert_select "tbody", /#{@idle.callsign}/
  end

  test "a hand-edited position filter is ignored rather than emptying the grid" do
    get teams_positions_roster_management_team_path(@team), params: { position: "has-999999" }

    assert_select "tbody tr", 2
  end

  # ------------------------------------------------------- preview step

  test "an action previews what would change and writes nothing" do
    assert_no_difference -> { PersonTeam.count } do
      post teams_positions_roster_management_preview_path(@team), params: remove_params([@idle])
    end

    assert_response :unprocessable_entity
    assert_select "[data-controller=scroll-to-top]"
    assert_select "body", /#{@idle.callsign}/
    assert_select "body", /Nothing has been saved/
  end

  test "the preview separates the people an action would skip" do
    post teams_positions_roster_management_preview_path(@team),
         params: action_params(RosterAction::GRANT_POSITION, [@idle, @veteran], position: @optional)

    assert_response :unprocessable_entity
    assert_select "body", /Skipped: 2 People/
    assert_select "body", /already holds #{@optional.title}/
  end

  test "previewing with no one selected says so and does not render a preview" do
    post teams_positions_roster_management_preview_path(@team), params: remove_params([])

    assert_redirected_to teams_positions_roster_management_team_path(@team)
    assert_match(/no one was selected/i, flash[:error])
  end

  test "an unknown action type is refused" do
    post teams_positions_roster_management_preview_path(@team),
         params: { action_type: "delete-everything", person_ids: [@idle.id] }

    assert_match(/not an action this page performs/i, flash[:error])
  end

  test "a position action without a position is refused" do
    post teams_positions_roster_management_preview_path(@team),
         params: { action_type: RosterAction::GRANT_POSITION, person_ids: [@idle.id] }

    assert_match(/choose a position/i, flash[:error])
  end

  # A position belonging to another team is not this page's to move.
  test "a position from another team is refused" do
    other = Position.create!(title: "Ops Lead", team_id: @other_team.id,
                             team_category: Position::TEAM_CATEGORY_OPTIONAL, active: true)

    post teams_positions_roster_management_preview_path(@team),
         params: action_params(RosterAction::GRANT_POSITION, [@idle], position: other)

    assert_match(/choose a position/i, flash[:error])
  end

  # ------------------------------------------------------- grant / revoke

  test "granting a position adds it only to the people who lack it" do
    PersonPosition.where(person_id: @idle.id, position_id: @optional.id).delete_all

    assert_difference -> { PersonPosition.where(position_id: @optional.id).count }, 1 do
      post teams_positions_roster_management_apply_path(@team),
           params: action_params(RosterAction::GRANT_POSITION, [@idle, @veteran], position: @optional)
    end

    assert PersonPosition.exists?(person_id: @idle.id, position_id: @optional.id)
    assert_match(/granted #{@optional.title}/i, flash[:success])
  end

  test "revoking a position removes it and leaves the team membership alone" do
    post teams_positions_roster_management_apply_path(@team),
         params: action_params(RosterAction::REVOKE_POSITION, [@idle], position: @optional)

    assert_not PersonPosition.exists?(person_id: @idle.id, position_id: @optional.id)
    assert PersonPosition.exists?(person_id: @idle.id, position_id: @recommended.id)
    assert PersonTeam.exists?(team_id: @team.id, person_id: @idle.id)
  end

  test "a position action can reach a public position, unlike removal from the team" do
    post teams_positions_roster_management_apply_path(@team),
         params: action_params(RosterAction::REVOKE_POSITION, [@idle], position: @public)

    assert_not PersonPosition.exists?(person_id: @idle.id, position_id: @public.id)
  end

  test "granting reports when no one needed the change" do
    post teams_positions_roster_management_apply_path(@team),
         params: action_params(RosterAction::GRANT_POSITION, [@idle], position: @optional)

    assert_match(/nothing to do/i, flash[:info])
  end

  # The team's own role grants ride on the membership, so they gate a removal
  # but not a position action -- even on a team with a single position, where
  # inferring it from the position list would collide.
  test "a team's role grant does not block a position action" do
    TeamRole.create!(team_id: @team.id, role_id: Role::ADMIN)
    PersonPosition.where(person_id: @idle.id, position_id: @optional.id).delete_all
    sign_in_as(@manager)

    post teams_positions_roster_management_apply_path(@team),
         params: action_params(RosterAction::GRANT_POSITION, [@idle], position: @optional)

    assert PersonPosition.exists?(person_id: @idle.id, position_id: @optional.id)
  end

  test "a manager cannot grant a position carrying a role they do not hold" do
    PositionRole.create!(position_id: @optional.id, role_id: Role::ADMIN)
    PersonPosition.where(person_id: @idle.id, position_id: @optional.id).delete_all
    sign_in_as(@manager)

    assert_no_difference -> { PersonPosition.count } do
      post teams_positions_roster_management_apply_path(@team),
           params: action_params(RosterAction::GRANT_POSITION, [@idle], position: @optional)
    end

    assert_match(/do not hold it yourself/i, flash[:error])
  end

  test "revoking a position purges the cached role set" do
    purged = []
    original = RoleManager.method(:purge_person)
    RoleManager.define_singleton_method(:purge_person) do |person_id|
      purged << person_id
      original.call(person_id)
    end

    post teams_positions_roster_management_apply_path(@team),
         params: action_params(RosterAction::REVOKE_POSITION, [@idle], position: @optional)

    assert_includes purged, @idle.id
  ensure
    RoleManager.define_singleton_method(:purge_person, original)
  end

  private

  # Every action now goes through the same two-step endpoint pair; the tests
  # post straight to apply, which re-derives and re-checks everything the
  # preview showed.
  def remove_params(people)
    { action_type: RosterAction::REMOVE_FROM_TEAM, person_ids: people.map(&:id) }
  end

  def action_params(type, people, position: nil)
    { action_type: type, position_id: position&.id, person_ids: people.map(&:id) }.compact
  end

  def create_position(title, category)
    Position.create!(title:, team_id: @team.id, team_category: category, active: true)
  end

  def add_timesheet(person, position, year)
    Timesheet.create!(person_id: person.id, position_id: position.id,
                      on_duty: Time.zone.local(year, 8, 25, 10, 0),
                      off_duty: Time.zone.local(year, 8, 25, 14, 0),
                      additional_notes: "roster test")
  end
end
