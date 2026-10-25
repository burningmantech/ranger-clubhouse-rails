# frozen_string_literal: true

require "test_helper"

class TeamsPositions::TeamRecordsControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role

  setup do
    Rails.cache.clear
    Current.reset

    @admin = person(:active_ranger)
    @tech_ninja = person(:echelon_ranger)
    @outsider = person(:inactive_ranger)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::TECH_NINJA, "Tech Ninja")
    # The index INNER JOINs team_role to role, so every granted role must exist
    # or the Role grants column silently stays empty.
    ensure_role(Role::MENTOR, "Mentor")
    ensure_role(Role::EDIT_SLOTS, "Edit Slots")
    ensure_role(Role::VC, "VC")
    grant_role(@admin, Role::ADMIN)
    grant_role(@tech_ninja, Role::TECH_NINJA)

    @team = teams(:dirt_team)
    @cadre = teams(:council_cadre)
    @inactive = teams(:inactive_cadre)

    # Grants and managers are built here rather than in test/fixtures: a global
    # team_role fixture would point at roles that only exist once a test calls
    # ensure_role, and PersonMembershipPresenter sorts those rows by role title.
    # Without them the index's Role grants and Managers columns are only ever
    # rendered empty.
    TeamRole.create!(team_id: @team.id, role_id: Role::MENTOR)
    TeamRole.create!(team_id: @team.id, role_id: Role::EDIT_SLOTS)
    TeamManager.create!(team_id: @team.id, person_id: @admin.id)
    TeamManager.create!(team_id: @team.id, person_id: person(:retired_ranger).id)

    sign_in_as(@admin)
  end

  teardown do
    Current.reset
    Rails.cache.clear
  end

  # ---------------------------------------------------------------- access

  test "denies access without the admin or tech ninja role" do
    sign_in_as(@outsider)

    get teams_positions_team_records_path

    assert_redirected_to me_root_path
    assert_equal "Admin or Tech Ninja role required to manage team records.", flash[:error]
  end

  test "allows access with only the tech ninja role" do
    sign_in_as(@tech_ninja)

    get teams_positions_team_records_path

    assert_response :success
  end

  # ----------------------------------------------------------------- index

  test "index lists every team with an edit link" do
    get teams_positions_team_records_path

    assert_response :success
    Team.order(:title).each do |team|
      assert_select "tr#team-#{team.id}"
      assert_select "a[href=?]", teams_positions_edit_team_record_path(team)
    end
  end

  # The roles and managers columns were the two nothing ever rendered with data,
  # so every assertion about them took the dash branch.
  test "index renders role grants and managers for a team that has them" do
    get teams_positions_team_records_path

    assert_response :success
    assert_select "tr#team-#{@team.id}" do
      assert_select "*", text: "Mentor"
      assert_select "*", text: "Edit Slots"
      assert_select "*", text: person(:active_ranger).callsign
      assert_select "*", text: person(:retired_ranger).callsign
    end
  end

  # Upstream orders managers by callsign, not by id or insertion order.
  test "index lists managers in callsign order" do
    get teams_positions_team_records_path

    expected = [person(:active_ranger).callsign, person(:retired_ranger).callsign].sort
    row = css_select("tr#team-#{@team.id}").first.to_s
    assert_operator row.index(expected.first), :<, row.index(expected.last)
  end

  test "index counts every team in the showing line" do
    get teams_positions_team_records_path

    assert_response :success
    assert_select "*", text: /Showing #{Team.count} of #{Team.count} teams/
  end

  test "index filters by type" do
    get teams_positions_team_records_path(type: Team::TYPE_CADRE)

    assert_response :success
    assert_select "tr#team-#{@cadre.id}"
    assert_select "tr#team-#{@team.id}", false, "a team row must not survive the cadre filter"
  end

  test "index filters by active status" do
    get teams_positions_team_records_path(active: "inactive")

    assert_response :success
    assert_select "tr#team-#{@inactive.id}"
    assert_select "tr#team-#{@team.id}", false, "an active team must not survive the inactive filter"
  end

  test "index filters by vehicle attributes in both directions" do
    @team.update!(mvr_eligible: true)
    @cadre.update!(mvr_eligible: false)

    get teams_positions_team_records_path(attribute: "mvr-eligible")
    assert_select "tr#team-#{@team.id}"
    assert_select "tr#team-#{@cadre.id}", false, "an ineligible team must not survive the eligible filter"

    get teams_positions_team_records_path(attribute: "mvr-ineligible")
    assert_select "tr#team-#{@cadre.id}"
    assert_select "tr#team-#{@team.id}", false, "an eligible team must not survive the ineligible filter"
  end

  # Every attribute the table draws a chip for must be filterable, or the column
  # shows a fact the reader cannot then narrow by.
  test "index filters by every attribute the table chips" do
    @team.update!(mvr_eligible: true, pvr_eligible: true, awards_eligible: true, include_in_directory: true)
    @cadre.update!(mvr_eligible: false, pvr_eligible: false, awards_eligible: false, include_in_directory: false)

    %w[mvr-eligible pvr-eligible awards-eligible in-directory].each do |attribute|
      get teams_positions_team_records_path(attribute:)

      assert_response :success
      assert_select "tr#team-#{@team.id}", true, "#{attribute} must keep the team that has it"
      assert_select "tr#team-#{@cadre.id}", false, "#{attribute} must drop the team that lacks it"
    end
  end

  test "index filters by a specific role grant" do
    get teams_positions_team_records_path(role: Role::MENTOR.to_s)

    assert_response :success
    assert_select "tr#team-#{@team.id}"
    assert_select "tr#team-#{@cadre.id}", false, "a team without the role must not survive"
  end

  test "index filters by having any or no role grants" do
    get teams_positions_team_records_path(role: "any")
    assert_select "tr#team-#{@team.id}"
    assert_select "tr#team-#{@cadre.id}", false, "a team with no grants must not survive the any filter"

    get teams_positions_team_records_path(role: "none")
    assert_select "tr#team-#{@cadre.id}"
    assert_select "tr#team-#{@team.id}", false, "a granting team must not survive the none filter"
  end

  # The subquery must not multiply rows: dirt_team carries two grants.
  test "the any-role filter lists a multi-grant team once" do
    get teams_positions_team_records_path(role: "any")

    assert_response :success
    assert_select "tr#team-#{@team.id}", count: 1
  end

  # A role no team grants would be a choice that can only return nothing.
  test "the role select offers only roles some team actually grants" do
    ensure_role(Role::VIEW_PII, "View Personal Info")

    get teams_positions_team_records_path

    assert_response :success
    assert_select "select[name=role] option[value=?]", Role::MENTOR.to_s
    assert_select "select[name=role] option[value=?]", Role::VIEW_PII.to_s, false,
                  "an ungranted role must not be offered"
  end

  test "an applied role filter draws a chip naming the role" do
    get teams_positions_team_records_path(role: Role::MENTOR.to_s)

    assert_response :success
    assert_select "*", text: /Role grant: Mentor/
  end

  test "index draws a removable chip for each applied filter" do
    get teams_positions_team_records_path(type: Team::TYPE_CADRE, active: "active")

    assert_response :success
    # Each chip's URL drops its own filter and keeps the other.
    assert_select "a[href=?]", teams_positions_team_records_path(active: "active")
    assert_select "a[href=?]", teams_positions_team_records_path(type: Team::TYPE_CADRE)
  end

  test "index shows the filter empty state when nothing matches" do
    Team.where(type: Team::TYPE_DELEGATION).find_each { |team| team.update!(active: true) }

    get teams_positions_team_records_path(type: Team::TYPE_DELEGATION, active: "inactive")

    assert_response :success
    assert_select "*", text: /No teams match the current filters/
  end

  # ------------------------------------------------------------ create/edit

  test "creates a team and lands on its row" do
    assert_difference "Team.count", 1 do
      post teams_positions_create_team_record_path,
           params: { team: { title: "Sandman Team", type: Team::TYPE_TEAM, active: "1" } }
    end

    team = Team.find_by(title: "Sandman Team")
    assert_redirected_to teams_positions_team_records_path(anchor: "team-#{team.id}")
    assert_equal "The team has been created.", flash[:success]
    assert_equal Team::TYPE_TEAM, team.type
  end

  test "rejects a blank title and redisplays the form" do
    assert_no_difference "Team.count" do
      post teams_positions_create_team_record_path,
           params: { team: { title: "", type: Team::TYPE_TEAM } }
    end

    assert_response :unprocessable_entity
    assert_select "*", text: /Title can't be blank\./
  end

  test "rejects an unknown team type" do
    assert_no_difference "Team.count" do
      post teams_positions_create_team_record_path,
           params: { team: { title: "Bogus Team", type: "wombat" } }
    end

    assert_response :unprocessable_entity
  end

  test "updates a team" do
    patch teams_positions_team_record_path(@team),
          params: { team: { title: "DIRT Team Renamed", type: @team.type, active: "1" } }

    assert_redirected_to teams_positions_team_records_path(anchor: "team-#{@team.id}")
    assert_equal "DIRT Team Renamed", @team.reload.title
  end

  # The automation columns are meaningless without awards eligibility, and
  # leaving them set would fire a grant against a team that no longer qualifies.
  test "clearing awards eligibility zeroes the awards automation columns" do
    @team.update!(awards_eligible: true, awards_auto_grant: true, awards_grants_service_year: true)

    patch teams_positions_team_record_path(@team),
          params: { team: { title: @team.title, type: @team.type, active: "1", awards_eligible: "0" } }

    @team.reload
    assert_not @team.awards_eligible
    assert_not @team.awards_auto_grant
    assert_not @team.awards_grants_service_year
  end

  # ------------------------------------------------------------ role grants

  # Setup grants Mentor and Edit Slots, so adding is proved with a role the team
  # does not hold and removing by dropping back to Mentor alone.
  test "tech ninja adds and removes role grants" do
    sign_in_as(@tech_ninja)

    patch teams_positions_team_record_path(@team),
          params: { team: { title: @team.title, type: @team.type, active: "1",
                            role_ids: ["", Role::MENTOR.to_s, Role::VC.to_s] } }

    assert_equal [Role::MENTOR, Role::VC].sort, TeamRole.where(team_id: @team.id).pluck(:role_id).sort
    assert ActionLog.exists?(event: "team-role-add")

    patch teams_positions_team_record_path(@team),
          params: { team: { title: @team.title, type: @team.type, active: "1", role_ids: [""] } }

    assert_empty TeamRole.where(team_id: @team.id)
    assert ActionLog.exists?(event: "team-role-remove")
  end

  # Upstream drops role_ids server-side for anyone but a Tech Ninja. The form
  # hides the section, so this only fires on a hand-made request.
  test "a plain admin cannot change role grants" do
    before = TeamRole.where(team_id: @team.id).pluck(:role_id).sort
    assert before.any?, "setup expectation: dirt_team carries role grants"

    patch teams_positions_team_record_path(@team),
          params: { team: { title: @team.title, type: @team.type, active: "1", role_ids: [""] } }

    assert_equal before, TeamRole.where(team_id: @team.id).pluck(:role_id).sort
  end

  test "the role grant checkboxes are shown only to a tech ninja" do
    get teams_positions_edit_team_record_path(@team)
    assert_select "input[name=?]", "team[role_ids][]", false

    sign_in_as(@tech_ninja)
    get teams_positions_edit_team_record_path(@team)
    assert_select "input[name=?][value=?]", "team[role_ids][]", Role::MENTOR.to_s
    # The whole row must be the label, or the 36px tap target is not clickable.
    assert_select "label.min-h-9 input[name=?]", "team[role_ids][]"
  end

  # --------------------------------------------------------------- destroy

  # The pin for the model's dependent: :destroy on positions. A bare
  # team.destroy would take the positions -- and their slots and sign-ups --
  # with it; upstream releases them instead.
  test "deleting a team releases its positions instead of destroying them" do
    position = Position.find_by(team_id: @cadre.id)
    assert position, "fixture expectation: council_cadre owns a position"

    assert_no_difference "Position.count" do
      delete teams_positions_team_record_path(@cadre)
    end

    assert_nil position.reload.team_id
  end

  # The memberships go through team.destroy!'s cascade (has_many :person_team,
  # dependent: :destroy), one at a time.
  #
  # Every child row is created here first: asserting a table is empty afterwards
  # proves nothing unless it held something to begin with, and the fixtures
  # attach no awards, logs, or managers to this cadre.
  test "deleting a team removes its memberships and logs the deletion" do
    assert PersonTeam.exists?(team_id: @cadre.id), "fixture expectation: council_cadre has members"
    TeamRole.create!(team_id: @cadre.id, role_id: Role::MENTOR)
    TeamManager.create!(team_id: @cadre.id, person_id: @admin.id)
    PersonTeamLog.create!(team_id: @cadre.id, person_id: @admin.id, joined_on: 1.year.ago)
    PersonAward.create!(team_id: @cadre.id, person_id: @admin.id, year: 2024,
                       notes: "Council Cadre member 2024")
    title = @cadre.title

    assert_difference "Team.count", -1 do
      delete teams_positions_team_record_path(@cadre)
    end

    assert_redirected_to teams_positions_team_records_path
    assert_equal "#{title} deleted.", flash[:success]
    assert_empty PersonTeam.where(team_id: @cadre.id)
    assert_empty TeamRole.where(team_id: @cadre.id)
    assert_empty PersonTeamLog.where(team_id: @cadre.id)
    assert_empty PersonAward.where(team_id: @cadre.id)
    # An orphan here keeps the person's "team manager" affordances alive, and
    # TeamManager.retrieve_teams_for_person raises on a row whose team is gone.
    assert_empty TeamManager.where(team_id: @cadre.id)
    assert ActionLog.exists?(event: "team-delete")
  end

  # ------------------------------------------------------------ malformed input

  # A malformed role_ids must not read as "revoke everything" (it would wipe the
  # grants) nor as "never posted" (the flash would claim a change that did not
  # happen). It is reported instead.
  test "a hand-posted non-array role_ids is rejected and changes nothing" do
    sign_in_as(@tech_ninja)
    before = TeamRole.where(team_id: @team.id).pluck(:role_id).sort

    patch teams_positions_team_record_path(@team),
          params: { team: { title: @team.title, type: @team.type, active: "1", role_ids: "5" } }

    assert_response :unprocessable_entity
    assert_nil flash[:success]
    assert_equal before, TeamRole.where(team_id: @team.id).pluck(:role_id).sort
  end

  test "role ids that are not ids are reported, not dropped" do
    sign_in_as(@tech_ninja)
    before = TeamRole.where(team_id: @team.id).pluck(:role_id).sort

    patch teams_positions_team_record_path(@team),
          params: { team: { title: @team.title, type: @team.type, active: "1", role_ids: ["", "abc"] } }

    assert_response :unprocessable_entity
    assert_match "were not submitted correctly", response.body
    assert_equal before, TeamRole.where(team_id: @team.id).pluck(:role_id).sort
  end

  test "an unknown role id is rejected without discarding the other edits" do
    sign_in_as(@tech_ninja)

    patch teams_positions_team_record_path(@team),
          params: { team: { title: "Renamed By Test", type: @team.type, active: "1",
                            role_ids: ["", "999999"] } }

    assert_response :unprocessable_entity
    assert_select "*", text: /name no role/
    assert_equal "DIRT Team", @team.reload.title
  end

  # Granting a role hands it to every member, so the two roles that could
  # escalate a whole roster need the actor to hold them already.
  test "a tech ninja cannot grant admin unless they hold it" do
    sign_in_as(@tech_ninja)

    patch teams_positions_team_record_path(@team),
          params: { team: { title: @team.title, type: @team.type, active: "1",
                            role_ids: ["", Role::ADMIN.to_s] } }

    assert_response :unprocessable_entity
    assert_not TeamRole.exists?(team_id: @team.id, role_id: Role::ADMIN)
  end

  test "an actor who holds admin may grant it" do
    grant_role(@tech_ninja, Role::ADMIN)
    sign_in_as(@tech_ninja)

    patch teams_positions_team_record_path(@team),
          params: { team: { title: @team.title, type: @team.type, active: "1",
                            role_ids: ["", Role::ADMIN.to_s] } }

    assert_response :redirect
    assert TeamRole.exists?(team_id: @team.id, role_id: Role::ADMIN)
  end

  test "a blank boolean is rejected instead of raising" do
    patch teams_positions_team_record_path(@team),
          params: { team: { title: @team.title, type: @team.type, active: "" } }

    assert_response :unprocessable_entity
    assert_select "*", text: /must be true or false/
  end

  # The read-only panel must show the team's real grants, never the caller's.
  test "a rejected form shows a plain admin the real role grants" do
    patch teams_positions_team_record_path(@team),
          params: { team: { title: "", type: @team.type, active: "1",
                            role_ids: ["", Role::ADMIN.to_s] } }

    assert_response :unprocessable_entity
    assert_select "*", text: "Mentor"
    assert_select "*", { text: "Admin", count: 0 }, "must not echo grants the caller posted"
  end

  test "saving keeps the filter the reader came from" do
    patch teams_positions_team_record_path(@team, active: "active"),
          params: { team: { title: @team.title, type: @team.type, active: "1" } }

    assert_redirected_to teams_positions_team_records_path(active: "active",
                                                           anchor: "team-#{@team.id}")
  end

  test "team create and update are recorded in the action log" do
    post teams_positions_create_team_record_path,
         params: { team: { title: "Audited Team", type: Team::TYPE_TEAM, active: "1" } }
    assert ActionLog.exists?(event: "team-create")

    patch teams_positions_team_record_path(@team),
          params: { team: { title: "Audited Rename", type: @team.type, active: "1" } }
    assert ActionLog.exists?(event: "team-update")
  end

  test "an unrecognized filter value narrows nothing and draws no chip" do
    get teams_positions_team_records_path(type: "wombat")

    assert_response :success
    assert_select "*", text: /Showing #{Team.count} of #{Team.count} teams/
    assert_select "*", { text: /Type: Wombat/, count: 0 }, "an unapplied filter must not draw a chip"
  end

  test "an over-long email is rejected instead of raising" do
    patch teams_positions_team_record_path(@team),
          params: { team: { title: @team.title, type: @team.type, active: "1",
                            email: "#{"a" * 250}@example.com" } }

    assert_response :unprocessable_entity
    assert_select "*", text: /characters or fewer/
  end

  # Upstream applies NullIfEmptyAttribute to email and description only, so
  # resource_tag deliberately keeps whatever the form posted.
  test "blank email and description are stored as null, not empty strings" do
    patch teams_positions_team_record_path(@team),
          params: { team: { title: @team.title, type: @team.type, active: "1",
                            email: "", description: "" } }

    @team.reload
    assert_nil @team.email
    assert_nil @team.description
  end
end
