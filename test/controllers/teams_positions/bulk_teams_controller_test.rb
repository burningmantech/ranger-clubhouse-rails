# frozen_string_literal: true

require "test_helper"

class TeamsPositions::BulkTeamsControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include DomIdTestHelper

  setup do
    Rails.cache.clear
    Current.reset

    @admin = person(:active_ranger)
    @manager = person(:retired_ranger)      # RetiredRanger -- Event Management + a team
    @outsider = person(:inactive_ranger)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::TECH_NINJA, "Tech Ninja")
    ensure_role(Role::EVENT_MANAGEMENT, "Event Management")
    grant_role(@admin, Role::ADMIN)
    grant_role(@manager, Role::EVENT_MANAGEMENT)

    @team = teams(:dirt_team)
    @other_team = teams(:operations_team)
    TeamManager.create!(team_id: @team.id, person_id: @manager.id)

    # team_category defaults to "public", so both of these say which they are.
    @recommended = Position.create!(title: "Dirt Patrol", team_id: @team.id, active: true,
                                    team_category: Position::TEAM_CATEGORY_ALL_MEMBERS)
    @optional = Position.create!(title: "Dirt Sweeper", team_id: @team.id, active: true,
                                 team_category: Position::TEAM_CATEGORY_OPTIONAL)

    @member = person(:auditor_ranger)       # AuditorTest -- joined below
    @newcomer = person(:alpha_ranger)       # AlphaNewbie -- no membership
    PersonTeam.create!(team_id: @team.id, person_id: @member.id)

    sign_in_as(@admin)
  end

  teardown do
    Current.reset
    Rails.cache.clear
  end

  # ---------------------------------------------------------------- access

  test "an admin reaches the form" do
    get teams_positions_bulk_teams_path

    assert_response :success
    assert_select "h1", /Bulk Grant \/ Revoke a Team/
  end

  test "a tech ninja reaches the form" do
    ninja = person(:echelon_ranger)
    grant_role(ninja, Role::TECH_NINJA)
    sign_in_as(ninja)

    get teams_positions_bulk_teams_path

    assert_response :success
  end

  test "a team manager reaches the form" do
    sign_in_as(@manager)
    get teams_positions_bulk_teams_path

    assert_response :success
  end

  # Managing a team is not by itself enough: this page hands out and takes away
  # memberships and the position grants that come with them.
  test "a team manager without Event Management or Admin is refused" do
    bare = person(:prospective_ranger)
    TeamManager.create!(team_id: @team.id, person_id: bare.id)
    sign_in_as(bare)

    get teams_positions_bulk_teams_path

    assert_redirected_to me_root_path
    assert_match(/event management or admin/i, flash[:error])
  end

  test "an Event Management person who manages no team is refused" do
    em = person(:prospective_ranger)
    grant_role(em, Role::EVENT_MANAGEMENT)
    sign_in_as(em)

    get teams_positions_bulk_teams_path

    assert_redirected_to me_root_path
  end

  test "someone who manages no team is refused" do
    sign_in_as(@outsider)
    get teams_positions_bulk_teams_path

    assert_redirected_to me_root_path
  end

  # ----------------------------------------------------------- the team list

  test "a team manager is offered only their own team" do
    sign_in_as(@manager)
    get teams_positions_bulk_teams_path

    assert_response :success
    assert_select "option", text: @team.title
    assert_select "option", text: @other_team.title, count: 0
  end

  test "an admin is offered every team" do
    get teams_positions_bulk_teams_path

    assert_response :success
    assert_select "option", text: @team.title
    assert_select "option", text: @other_team.title
  end

  # Upstream refuses these teams outright, for everyone including an admin: no
  # one makes two hundred admins in one POST.
  test "a team granting Admin is not offered even to an admin" do
    TeamRole.create!(team_id: @team.id, role_id: Role::ADMIN)

    get teams_positions_bulk_teams_path

    assert_response :success
    assert_select "select[name=team_id]"
    assert_select "option", text: @other_team.title
    assert_select "option", text: @team.title, count: 0
  end

  test "a team granting Admin cannot be reached by posting its id" do
    TeamRole.create!(team_id: @team.id, role_id: Role::ADMIN)

    assert_no_difference "PersonTeam.count" do
      post teams_positions_apply_bulk_teams_path, params: preview_params(@newcomer.callsign)
    end

    assert_response :unprocessable_entity
    assert_match(/choose a team/i, flash[:error])
  end

  test "an inactive team is offered but labelled" do
    @team.update!(active: false)
    get teams_positions_bulk_teams_path

    assert_select "option", text: "#{@team.title} (inactive)"
  end

  # The grouping this page adds over its position sibling: an admin sees every
  # kind in one select, and a cadre is not a team.
  test "teams, cadres and delegations are grouped under their own headings" do
    get teams_positions_bulk_teams_path

    assert_select "optgroup[label=Teams] option", text: @team.title
    assert_select "optgroup[label=Cadres] option", text: teams(:council_cadre).title
    assert_select "optgroup[label=Delegations] option", text: teams(:khaki_team).title
  end

  # team.type is a plain string column on a table the Laravel app also writes,
  # so a fourth kind must still reach the list. Vanishing silently would read as
  # a deleted team on the only page that can grant it.
  test "a team of an unexpected type still appears rather than vanishing" do
    @other_team.update_columns(type: "workgroup")

    get teams_positions_bulk_teams_path

    assert_response :success
    assert_select "optgroup[label=Workgroups] option", text: @other_team.title
  end

  # The branch unique to this page's stricter ban: teams are managed, but every
  # one of them confers a guarded role.
  test "a manager whose only team grants Admin is told why the list is empty" do
    TeamRole.create!(team_id: @team.id, role_id: Role::ADMIN)
    sign_in_as(@manager)

    get teams_positions_bulk_teams_path

    assert_response :success
    assert_select "select[name=team_id]", count: 0
    assert_select "body", /no teams you can grant or revoke/i
  end

  # --------------------------------------------------------------- preview

  test "preview writes nothing and shows every line" do
    assert_no_difference ["PersonTeam.count", "PersonPosition.count"] do
      post teams_positions_preview_bulk_teams_path,
           params: preview_params("#{@newcomer.callsign}\n#{@member.callsign}\nNobody")
    end

    assert_response :unprocessable_entity
    assert_select "h1", /Grant DIRT Team to 1 person/
    assert_select "tbody tr", 3
    assert_unique_dom_ids
  end

  # The consequence the form cannot show on its face, and the reason this page
  # is not just a membership editor.
  test "a grant preview names the Recommended positions it also grants" do
    post teams_positions_preview_bulk_teams_path, params: preview_params(@newcomer.callsign)

    assert_select "body", /Also grants #{@recommended.title}/
    assert_select "body", { text: /#{@optional.title}/, count: 0 }
  end

  test "a revoke preview names both position kinds and the cancelled sign-ups" do
    post teams_positions_preview_bulk_teams_path,
         params: preview_params(@member.callsign, direction: "revoke")

    assert_select "body", /Also revokes #{@recommended.title} and #{@optional.title}/
    # "Upcoming", not "already signed up for": the sweep only reaches this
    # year's future slots, so a broader promise would be untrue after the event.
    assert_select "body", /upcoming shifts/i
  end

  # The team is given a Public position on purpose: with no positions at all the
  # assertion would pass without the team_category filter ever being exercised,
  # so dropping that filter -- and handing over Public positions with every
  # membership -- would leave this test green.
  test "a team with no positions of the moved kind says so rather than staying silent" do
    Position.create!(title: "Ops Open House", team_id: @other_team.id, active: true,
                     team_category: Position::TEAM_CATEGORY_PUBLIC)

    post teams_positions_preview_bulk_teams_path,
         params: preview_params(@newcomer.callsign, team: @other_team)

    assert_select "body", /no Recommended positions/
    assert_select "body", { text: /Ops Open House/, count: 0 }
  end

  # With nothing to confirm the button is hidden, so the page has to say why
  # rather than offer to continue with no one.
  test "a preview with nothing to change says so and offers no confirm button" do
    post teams_positions_preview_bulk_teams_path, params: preview_params("No one\nAlsoNobody")

    assert_response :unprocessable_entity
    assert_select "body", /There is nothing to confirm/
    # Exactly one submit, and it is the way back. Asserting only that a
    # formaction button exists would match "Go Back and Edit" and pass even if a
    # confirm button reading "Grant DIRT Team to 0 people" were rendered beside
    # it -- which is the whole behavior this test is named for.
    assert_select "input[type=submit]", 1
    assert_select "input[type=submit][formaction][value=?]", "Go Back and Edit"
  end

  test "preview re-posts the pasted list for the apply step" do
    post teams_positions_preview_bulk_teams_path, params: preview_params(@newcomer.callsign)

    assert_select "input[name=callsigns][value=?]", @newcomer.callsign
    assert_select "input[name=team_id][value=?]", @team.id.to_s
    assert_select "input[name=direction][value=grant]"
  end

  test "preview with no direction chosen re-renders the form with the list intact" do
    post teams_positions_preview_bulk_teams_path,
         params: { team_id: @team.id, callsigns: @newcomer.callsign }

    assert_response :unprocessable_entity
    assert_match(/grant or revoke/i, flash[:error])
    assert_select "textarea[name=callsigns]", text: /#{@newcomer.callsign}/
  end

  test "preview with an empty list re-renders the form" do
    post teams_positions_preview_bulk_teams_path, params: preview_params("   \n  ")

    assert_response :unprocessable_entity
    assert_match(/at least one callsign/i, flash[:error])
  end

  test "a team manager cannot preview a team they do not manage" do
    sign_in_as(@manager)
    post teams_positions_preview_bulk_teams_path,
         params: preview_params(@newcomer.callsign, team: @other_team)

    assert_response :unprocessable_entity
    assert_match(/choose a team/i, flash[:error])
  end

  # ----------------------------------------------------------------- apply

  # The report of what happened lives on the page, not in a toast that clips a
  # long list and dismisses itself -- and the pasted list survives with it.
  test "apply grants the membership and its Recommended position, and reports on the page" do
    assert_difference -> { PersonTeam.where(team_id: @team.id).count } => 1,
                      -> { PersonPosition.where(person_id: @newcomer.id).count } => 1 do
      post teams_positions_apply_bulk_teams_path, params: preview_params(@newcomer.callsign)
    end

    assert_response :unprocessable_entity
    assert_select "[data-controller=scroll-to-top]"
    assert_select "body", /Granted DIRT Team to 1 person/
    assert_select "body", /Changed: #{@newcomer.callsign}/
    assert_select "textarea[name=callsigns]", text: /#{@newcomer.callsign}/
  end

  test "apply revokes the membership and both position kinds" do
    PersonPosition.create!(person_id: @member.id, position_id: @recommended.id)
    PersonPosition.create!(person_id: @member.id, position_id: @optional.id)

    assert_difference -> { PersonTeam.where(team_id: @team.id).count } => -1,
                      -> { PersonPosition.where(person_id: @member.id).count } => -2 do
      post teams_positions_apply_bulk_teams_path,
           params: preview_params(@member.callsign, direction: "revoke")
    end

    assert_select "body", /Revoked DIRT Team from 1 person/
  end

  test "apply says so when the whole list needed no change" do
    post teams_positions_apply_bulk_teams_path, params: preview_params(@member.callsign)

    assert_select "body", /Nothing was changed/
    # "Needed no action" rather than a claim about their state: this bucket also
    # holds repeated lines, including repeats of a callsign matching no one.
    assert_select "body", /1 callsign needed no action/
  end

  # The opposite of "nothing needed changing": nothing could be used at all.
  # The bad callsigns are named, because the apply re-renders the form and the
  # per-line table that identified them is no longer on the page.
  test "apply distinguishes an unusable list from one that needed no change" do
    post teams_positions_apply_bulk_teams_path, params: preview_params("No one\nAlsoNobody")

    assert_select "body", /Nothing was changed/
    assert_select "body", /Could not be used: No one and AlsoNobody/
  end

  # Colour is what a reader scanning the page acts on, so a run that wrote
  # nothing must not wear the same green as one that worked.
  test "an apply that changed nothing is not painted as a success" do
    post teams_positions_apply_bulk_teams_path, params: preview_params("No one\nAlsoNobody")

    assert_select ".box-success", count: 0
    # Matched on the banner's own text: the page carries a standing
    # ".box-warning" advisory about positions, so a bare class assertion would
    # pass whatever colour the banner actually wore.
    assert_select ".box-warning", /Nothing was changed/
  end

  test "an apply that fully succeeded is painted as a success" do
    post teams_positions_apply_bulk_teams_path, params: preview_params(@newcomer.callsign)

    assert_select ".box-success"
    assert_select "body", { text: /fix anything that did not go through/, count: 0 }
  end

  # Something changed, but something else needs attention -- amber, not green.
  test "an apply with problems alongside changes is not painted as a success" do
    post teams_positions_apply_bulk_teams_path,
         params: preview_params("#{@newcomer.callsign}\nNobody")

    assert_select ".box-success", count: 0
    assert_select ".box-warning", /Granted DIRT Team to 1 person/
  end

  # The preview is a description, not an authority: apply re-checks every gate
  # from its own params, so posting straight past the preview changes nothing.
  test "a team manager cannot apply to a team they do not manage" do
    sign_in_as(@manager)

    assert_no_difference "PersonTeam.count" do
      post teams_positions_apply_bulk_teams_path,
           params: preview_params(@newcomer.callsign, team: @other_team)
    end

    assert_response :unprocessable_entity
  end

  test "someone who manages no team cannot apply" do
    sign_in_as(@outsider)

    assert_no_difference "PersonTeam.count" do
      post teams_positions_apply_bulk_teams_path, params: preview_params(@newcomer.callsign)
    end

    assert_redirected_to me_root_path
  end

  # --------------------------------------------------------------- guards

  # The team itself carries no guarded role -- that is the ban above -- but one
  # of the positions it hands over still can. Refused up front rather than left
  # to raise once per person half way through a confirmed list.
  test "a team whose Recommended position grants Admin is refused to a manager without the role" do
    PositionRole.create!(position_id: @recommended.id, role_id: Role::ADMIN)
    sign_in_as(@manager)

    assert_no_difference "PersonTeam.count" do
      post teams_positions_apply_bulk_teams_path, params: preview_params(@newcomer.callsign)
    end

    assert_response :unprocessable_entity
    assert_match(/cannot be handed out here/i, flash[:error])
  end

  # Moving a role grant is moving a real permission in either direction. Revoke
  # is the direction that turns on whether the actor holds the role, so this is
  # the message that names it.
  test "revoking a team whose position grants Admin is refused to a manager without the role" do
    PositionRole.create!(position_id: @optional.id, role_id: Role::ADMIN)
    sign_in_as(@manager)

    assert_no_difference "PersonTeam.count" do
      post teams_positions_apply_bulk_teams_path,
           params: preview_params(@member.callsign, direction: "revoke")
    end

    assert_response :unprocessable_entity
    assert_match(/do not hold it yourself/i, flash[:error])
  end

  # The ban stated on reject_guarded would be trivially bypassable otherwise:
  # pick the team rather than the position and the same two hundred admins get
  # made in the same one POST. The sibling page refuses the equivalent grant for
  # everyone, and so does this one.
  test "granting a team whose position grants Admin is refused even for an admin" do
    PositionRole.create!(position_id: @recommended.id, role_id: Role::ADMIN)

    assert_no_difference ["PersonTeam.count", "PersonPosition.count"] do
      post teams_positions_apply_bulk_teams_path, params: preview_params(@newcomer.callsign)
    end

    assert_response :unprocessable_entity
    assert_match(/cannot be handed out here/i, flash[:error])
  end

  # Revoking is the mirror of Roster Management's rule: allowed to whoever holds
  # the role themselves.
  test "an admin may revoke a team whose position grants Admin" do
    PositionRole.create!(position_id: @recommended.id, role_id: Role::ADMIN)

    assert_difference -> { PersonTeam.where(team_id: @team.id).count } => -1 do
      post teams_positions_apply_bulk_teams_path,
           params: preview_params(@member.callsign, direction: "revoke")
    end
  end

  # An Optional position is not handed over by a grant, so its role grant is not
  # the grant's business either.
  test "a grant is not blocked by a role on a position it does not move" do
    PositionRole.create!(position_id: @optional.id, role_id: Role::ADMIN)
    sign_in_as(@manager)

    assert_difference -> { PersonTeam.where(team_id: @team.id).count } => 1 do
      post teams_positions_apply_bulk_teams_path, params: preview_params(@newcomer.callsign)
    end
  end

  # ------------------------------------------------------------------ edit

  # 422, not 200: Turbo discards a 200 answer to a form submission, so a 200
  # here would leave the button doing nothing in a browser.
  test "the edit step re-renders the form with everything still filled in" do
    post teams_positions_edit_bulk_teams_path, params: preview_params("No one\n#{@newcomer.callsign}")

    assert_response :unprocessable_entity
    assert_select "textarea[name=callsigns]", text: /No one/
    assert_select "option[selected][value=?]", @team.id.to_s
    assert_select "input[name=direction][value=grant][checked]"
  end

  test "the plain form still answers 200" do
    get teams_positions_bulk_teams_path

    assert_response :success
  end

  test "an array-shaped team_id is refused rather than raising" do
    post teams_positions_preview_bulk_teams_path,
         params: { team_id: [@team.id], direction: "grant", callsigns: @newcomer.callsign }

    assert_response :unprocessable_entity
    assert_match(/choose a team/i, flash[:error])
  end

  test "an array-shaped team_id on the form page does not raise" do
    get teams_positions_bulk_teams_path, params: { team_id: [@team.id] }

    assert_response :success
  end

  private

  def preview_params(callsigns, team: nil, direction: "grant")
    { team_id: (team || @team).id, direction:, callsigns: }
  end
end
