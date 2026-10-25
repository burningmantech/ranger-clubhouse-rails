# frozen_string_literal: true

require "test_helper"

class TeamsPositions::BulkPositionsControllerTest < ActionDispatch::IntegrationTest
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

    @position = Position.create!(title: "Dirt Patrol", team_id: @team.id, active: true)
    @other_position = Position.create!(title: "Ops Desk", team_id: @other_team.id, active: true)

    @holder = person(:auditor_ranger)       # AuditorTest -- granted below
    @newcomer = person(:alpha_ranger)       # AlphaNewbie -- holds nothing
    PersonPosition.create!(person_id: @holder.id, position_id: @position.id)

    sign_in_as(@admin)
  end

  teardown do
    Current.reset
    Rails.cache.clear
  end

  # ---------------------------------------------------------------- access

  test "an admin reaches the form" do
    get teams_positions_bulk_positions_path

    assert_response :success
    assert_select "h1", /Bulk Grant/
  end

  test "a tech ninja reaches the form" do
    ninja = person(:echelon_ranger)
    grant_role(ninja, Role::TECH_NINJA)
    sign_in_as(ninja)

    get teams_positions_bulk_positions_path

    assert_response :success
  end

  test "a team manager reaches the form" do
    sign_in_as(@manager)
    get teams_positions_bulk_positions_path

    assert_response :success
  end

  # Managing a team is not by itself enough: this page hands out and takes away
  # position grants, the same writes Roster Management gates on the same pair.
  test "a team manager without Event Management or Admin is refused" do
    bare = person(:prospective_ranger)
    TeamManager.create!(team_id: @team.id, person_id: bare.id)
    sign_in_as(bare)

    get teams_positions_bulk_positions_path

    assert_redirected_to me_root_path
    assert_match(/event management or admin/i, flash[:error])
  end

  test "an Event Management person who manages no team is refused" do
    em = person(:prospective_ranger)
    grant_role(em, Role::EVENT_MANAGEMENT)
    sign_in_as(em)

    get teams_positions_bulk_positions_path

    assert_redirected_to me_root_path
  end

  test "someone who manages no team is refused" do
    sign_in_as(@outsider)
    get teams_positions_bulk_positions_path

    assert_redirected_to me_root_path
  end

  # ------------------------------------------------------- the position list

  test "a team manager is offered only their own team's positions" do
    sign_in_as(@manager)
    get teams_positions_bulk_positions_path

    assert_response :success
    assert_select "option", text: @position.title
    assert_select "option", text: @other_position.title, count: 0
  end

  test "an admin is offered positions from every team" do
    get teams_positions_bulk_positions_path

    assert_response :success
    assert_select "option", text: @position.title
    assert_select "option", text: @other_position.title
  end

  # The rule Roster Management applies to the same writes: no one moves a role
  # grant they do not hold themselves, in either direction.
  # A second, unguarded position on the same team, so the select actually
  # renders: without one the page falls to its empty state and a count: 0
  # assertion passes on a page that has no options at all.
  test "a position granting Admin is not offered to someone without the role" do
    PositionRole.create!(position_id: @position.id, role_id: Role::ADMIN)
    ordinary = Position.create!(title: "Dirt Sweeper", team_id: @team.id, active: true)
    sign_in_as(@manager)

    get teams_positions_bulk_positions_path

    assert_response :success
    assert_select "select[name=position_id]"
    assert_select "option", text: ordinary.title
    assert_select "option", text: @position.title, count: 0
  end

  test "a position granting Admin is offered to an admin" do
    PositionRole.create!(position_id: @position.id, role_id: Role::ADMIN)

    get teams_positions_bulk_positions_path

    assert_response :success
    assert_select "option", text: @position.title
  end

  test "an inactive position is offered but labelled" do
    @position.update!(active: false)
    get teams_positions_bulk_positions_path

    assert_select "option", text: "#{@position.title} (inactive)"
  end

  # -------------------------------------------------------------- preview

  test "preview writes nothing and shows every line" do
    assert_no_difference "PersonPosition.count" do
      post teams_positions_preview_bulk_positions_path,
           params: preview_params("#{@newcomer.callsign}\n#{@holder.callsign}\nNobody")
    end

    assert_response :unprocessable_entity
    assert_select "h1", /Grant Dirt Patrol to 1 person/
    assert_select "tbody tr", 3
    assert_unique_dom_ids
  end

  # With nothing to confirm the button is hidden, so the page has to say why
  # rather than offer to continue with no one.
  test "a preview with nothing to change says so and offers no confirm button" do
    post teams_positions_preview_bulk_positions_path, params: preview_params("No one\nAlsoNobody")

    assert_response :unprocessable_entity
    assert_select "body", /There is nothing to confirm/
    assert_select "input[type=submit][formaction]"
    assert_select "body", { text: /continue/, count: 0 }
  end

  test "a revoke preview warns that sign-ups are cancelled too" do
    post teams_positions_preview_bulk_positions_path,
         params: preview_params(@holder.callsign, direction: "revoke")

    assert_select "body", /also cancels their sign-ups/i
  end

  test "preview re-posts the pasted list for the apply step" do
    post teams_positions_preview_bulk_positions_path, params: preview_params(@newcomer.callsign)

    assert_select "input[name=callsigns][value=?]", @newcomer.callsign
    assert_select "input[name=position_id][value=?]", @position.id.to_s
    assert_select "input[name=direction][value=grant]"
  end

  test "preview with no direction chosen re-renders the form with the list intact" do
    post teams_positions_preview_bulk_positions_path,
         params: { position_id: @position.id, callsigns: @newcomer.callsign }

    assert_response :unprocessable_entity
    assert_match(/grant or revoke/i, flash[:error])
    assert_select "textarea[name=callsigns]", text: /#{@newcomer.callsign}/
  end

  test "preview with an empty list re-renders the form" do
    post teams_positions_preview_bulk_positions_path, params: preview_params("   \n  ")

    assert_response :unprocessable_entity
    assert_match(/at least one callsign/i, flash[:error])
  end

  test "a team manager cannot preview a position they do not manage" do
    sign_in_as(@manager)
    post teams_positions_preview_bulk_positions_path,
         params: preview_params(@newcomer.callsign, position: @other_position)

    assert_response :unprocessable_entity
    assert_match(/choose a position/i, flash[:error])
  end

  # ---------------------------------------------------------------- apply

  # The report of what happened lives on the page, not in a toast that clips a
  # long list and dismisses itself -- and the pasted list survives with it.
  test "apply grants the position and reports what changed on the page" do
    assert_difference "PersonPosition.where(position_id: @position.id).count", 1 do
      post teams_positions_apply_bulk_positions_path, params: preview_params(@newcomer.callsign)
    end

    assert_response :unprocessable_entity
    assert_select "[data-controller=scroll-to-top]"
    assert_select "body", /Granted Dirt Patrol to 1 person/
    assert_select "body", /Changed: #{@newcomer.callsign}/
    assert_select "textarea[name=callsigns]", text: /#{@newcomer.callsign}/
  end

  test "apply revokes the position" do
    assert_difference "PersonPosition.where(position_id: @position.id).count", -1 do
      post teams_positions_apply_bulk_positions_path,
           params: preview_params(@holder.callsign, direction: "revoke")
    end

    assert_select "body", /Revoked Dirt Patrol from 1 person/
  end

  test "apply says so when the whole list needed no change" do
    post teams_positions_apply_bulk_positions_path, params: preview_params(@holder.callsign)

    assert_select "body", /Nothing was changed/
    assert_select "body", /1 callsign already had the right state/
  end

  # The opposite of "nothing needed changing": nothing could be used at all.
  test "apply distinguishes an unusable list from one that needed no change" do
    post teams_positions_apply_bulk_positions_path, params: preview_params("No one\nAlsoNobody")

    assert_select "body", /Nothing was changed/
    assert_select "body", /2 callsigns could not be used/
  end

  # The preview is a description, not an authority: apply re-checks the gate
  # from its own params, so posting straight past the preview changes nothing.
  test "a team manager cannot apply to a position they do not manage" do
    sign_in_as(@manager)

    assert_no_difference "PersonPosition.count" do
      post teams_positions_apply_bulk_positions_path,
           params: preview_params(@newcomer.callsign, position: @other_position)
    end

    assert_response :unprocessable_entity
  end

  test "a team manager cannot apply to a position granting a role they lack" do
    PositionRole.create!(position_id: @position.id, role_id: Role::ADMIN)
    sign_in_as(@manager)

    assert_no_difference "PersonPosition.count" do
      post teams_positions_apply_bulk_positions_path, params: preview_params(@newcomer.callsign)
    end

    assert_response :unprocessable_entity
  end

  # Upstream guards only the grant. Taking a role-bearing position away is
  # moving the same permission, so this port refuses both directions.
  test "a team manager cannot revoke a position granting a role they lack" do
    PositionRole.create!(position_id: @position.id, role_id: Role::ADMIN)
    sign_in_as(@manager)

    assert_no_difference "PersonPosition.count" do
      post teams_positions_apply_bulk_positions_path,
           params: preview_params(@holder.callsign, direction: "revoke")
    end

    assert_response :unprocessable_entity
    assert_match(/choose a position/i, flash[:error])
  end

  test "someone who manages no team cannot apply" do
    sign_in_as(@outsider)

    assert_no_difference "PersonPosition.count" do
      post teams_positions_apply_bulk_positions_path, params: preview_params(@newcomer.callsign)
    end

    assert_redirected_to me_root_path
  end

  # ----------------------------------------------------------------- edit

  # 422, not 200: Turbo discards a 200 answer to a form submission, so a 200
  # here would leave the button doing nothing in a browser.
  test "the edit step re-renders the form with everything still filled in" do
    post teams_positions_edit_bulk_positions_path, params: preview_params("No one\n#{@newcomer.callsign}")

    assert_response :unprocessable_entity
    assert_select "textarea[name=callsigns]", text: /No one/
    assert_select "option[selected][value=?]", @position.id.to_s
    assert_select "input[name=direction][value=grant][checked]"
  end

  test "the plain form still answers 200" do
    get teams_positions_bulk_positions_path

    assert_response :success
  end

  # --------------------------------------------------------------- guards

  # Upstream refuses this for everyone, admins included: no one makes two
  # hundred admins in one POST.
  test "granting a position that carries Admin is refused even for an admin" do
    PositionRole.create!(position_id: @position.id, role_id: Role::ADMIN)

    assert_no_difference "PersonPosition.count" do
      post teams_positions_apply_bulk_positions_path, params: preview_params(@newcomer.callsign)
    end

    assert_response :unprocessable_entity
    assert_match(/cannot be handed out here/i, flash[:error])
  end

  test "revoking a position that carries Admin is still allowed for an admin" do
    PositionRole.create!(position_id: @position.id, role_id: Role::ADMIN)

    assert_difference "PersonPosition.where(position_id: @position.id).count", -1 do
      post teams_positions_apply_bulk_positions_path,
           params: preview_params(@holder.callsign, direction: "revoke")
    end
  end

  test "an array-shaped position_id is refused rather than raising" do
    post teams_positions_preview_bulk_positions_path,
         params: { position_id: [@position.id], direction: "grant", callsigns: @newcomer.callsign }

    assert_response :unprocessable_entity
    assert_match(/choose a position/i, flash[:error])
  end

  test "an array-shaped position_id on the form page does not raise" do
    get teams_positions_bulk_positions_path, params: { position_id: [@position.id] }

    assert_response :success
  end

  private

  def preview_params(callsigns, position: nil, direction: "grant")
    { position_id: (position || @position).id, direction:, callsigns: }
  end
end
