# frozen_string_literal: true

require "test_helper"

class TeamsPositions::BulkMembershipHistoryControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include DomIdTestHelper

  setup do
    Rails.cache.clear
    Current.reset

    @admin = person(:active_ranger)
    # Holds no role at all -- the point of this page's gate is that a plain
    # Clubhouse Team Manager reaches it, where the sibling bulk pages refuse
    # anyone without Event Management or Admin.
    @manager = person(:echelon_ranger)
    @outsider = person(:inactive_ranger)
    @target = person(:auditor_ranger)

    ensure_role(Role::ADMIN, "Admin")
    grant_role(@admin, Role::ADMIN)

    @team = teams(:dirt_team)
    @other_team = teams(:operations_team)
    TeamManager.create!(team_id: @team.id, person_id: @manager.id)

    sign_in_as(@admin)
  end

  teardown do
    Current.reset
    Rails.cache.clear
  end

  def preview_params(records, team: @team, action: "team_membership", reason: nil)
    { bulk_action: action, records:, team_id: team&.id, reason: }.compact
  end

  def line(joined_on = "2024-08-01", left_on = nil)
    [@target.callsign, joined_on, left_on].compact.join(",")
  end

  # ---------------------------------------------------------------- access

  test "an admin reaches the form" do
    get teams_positions_bulk_membership_history_path

    assert_response :success
    assert_select "h1", /Bulk Record Team Membership History/
    assert_unique_dom_ids
  end

  test "a team manager holding no role reaches the form" do
    sign_in_as(@manager)

    get teams_positions_bulk_membership_history_path

    assert_response :success
    assert_select "h1", /Bulk Record Team Membership History/
  end

  test "someone who is neither an admin nor a team manager is turned away" do
    sign_in_as(@outsider)

    get teams_positions_bulk_membership_history_path

    assert_redirected_to me_root_path
    assert_match(/admin role, or a team to manage/i, flash[:error])
  end

  # ------------------------------------------------------------- the lists

  test "the action is offered as a select even though there is only one" do
    get teams_positions_bulk_membership_history_path

    assert_select "select[name=bulk_action] option[value=team_membership]",
                  text: "Add Team Membership History"
  end

  test "a team manager is offered only the teams they manage" do
    sign_in_as(@manager)

    get teams_positions_bulk_membership_history_path

    assert_response :success
    assert_select "select[name=team_id] option", text: @team.title
    assert_select "select[name=team_id] option", text: @other_team.title, count: 0
  end

  test "an admin is offered every team" do
    get teams_positions_bulk_membership_history_path

    assert_select "select[name=team_id] option", text: @team.title
    assert_select "select[name=team_id] option", text: @other_team.title
  end

  # A team the reader cannot reach and one that does not exist answer
  # identically: the select is the only source of a valid id.
  test "a hand-posted team outside the manageable set is refused" do
    sign_in_as(@manager)

    assert_no_difference "PersonTeamLog.count" do
      post teams_positions_preview_bulk_membership_history_path,
           params: preview_params(line, team: @other_team)
    end

    assert_response :unprocessable_entity
    assert_match(/choose a team/i, flash[:error])
  end

  test "a team id matching no team is refused" do
    post teams_positions_preview_bulk_membership_history_path,
         params: preview_params(line).merge(team_id: 0)

    assert_response :unprocessable_entity
    assert_match(/choose a team/i, flash[:error])
  end

  # --------------------------------------------------------------- preview

  test "preview writes nothing" do
    assert_no_difference "PersonTeamLog.count" do
      post teams_positions_preview_bulk_membership_history_path, params: preview_params(line)
    end

    assert_response :unprocessable_entity
    assert_select "h1", /Add Team Membership History/
    assert_select "tbody tr", 1
    assert_unique_dom_ids
  end

  test "preview names the whole span when the person has left" do
    post teams_positions_preview_bulk_membership_history_path,
         params: preview_params(line("2024-08-01", "2024-09-05"))

    assert_response :unprocessable_entity
    assert_select "tbody tr td", /Joined 2024-08-01, left 2024-09-05/
  end

  test "preview names an open span without inventing a leaving date" do
    post teams_positions_preview_bulk_membership_history_path, params: preview_params(line)

    assert_select "tbody tr td", /Joined 2024-08-01/
    assert_select "tbody tr td", { text: /left/, count: 0 }
  end

  test "preview marks an unknown callsign as a problem" do
    post teams_positions_preview_bulk_membership_history_path,
         params: preview_params("NotARealCallsign,2024-08-01")

    assert_response :unprocessable_entity
    assert_select "tbody tr td", /Callsign not found/
    # No confirm button: nothing on the list can be recorded.
    assert_select "input[type=submit]", 1
  end

  test "preview marks a line with no date as a problem" do
    post teams_positions_preview_bulk_membership_history_path,
         params: preview_params(@target.callsign)

    assert_response :unprocessable_entity
    assert_select "tbody tr td", /Missing joined on date/
  end

  # The format is refused rather than guessed at: Ruby reads 08/01/2024 as
  # 8 January and upstream's Carbon reads it as August 1st.
  test "preview refuses a joined on date that is not YYYY-MM-DD" do
    post teams_positions_preview_bulk_membership_history_path,
         params: preview_params(line("08/01/2024"))

    assert_response :unprocessable_entity
    assert_select "tbody tr td", /Joined on date must be YYYY-MM-DD/
  end

  test "preview refuses a date that looks right but is not on the calendar" do
    post teams_positions_preview_bulk_membership_history_path,
         params: preview_params(line("2024-02-31"))

    assert_response :unprocessable_entity
    assert_select "tbody tr td", /Joined on date must be YYYY-MM-DD/
  end

  test "preview refuses a left on date that is not YYYY-MM-DD" do
    post teams_positions_preview_bulk_membership_history_path,
         params: preview_params(line("2024-08-01", "last summer"))

    assert_response :unprocessable_entity
    assert_select "tbody tr td", /Left on date must be YYYY-MM-DD/
  end

  # PersonTeamLog refuses this pair, so it is caught in the preview rather than
  # arriving as a failed line after the reader has confirmed.
  test "preview marks a leaving date before the joining date as a problem" do
    post teams_positions_preview_bulk_membership_history_path,
         params: preview_params(line("2024-09-05", "2024-08-01"))

    assert_response :unprocessable_entity
    assert_select "tbody tr td", /before joined on/
  end

  test "preview refuses a line carrying a fourth column" do
    post teams_positions_preview_bulk_membership_history_path,
         params: preview_params("#{@target.callsign},2024-08-01,2024-09-05,DIRT Team")

    assert_response :unprocessable_entity
    assert_select "tbody tr td", /Too many columns/
  end

  test "preview marks a locked account as a problem and never writes to it" do
    locked = person(:deceased_ranger)

    assert_no_difference "PersonTeamLog.count" do
      post teams_positions_preview_bulk_membership_history_path,
           params: preview_params("#{locked.callsign},2024-08-01")
    end

    assert_select "tbody tr td", /account is locked/i
    assert_select "input[type=submit]", 1
  end

  test "preview re-posts everything the apply needs, the team included" do
    post teams_positions_preview_bulk_membership_history_path,
         params: preview_params(line, reason: "roster archaeology")

    assert_select "input[name=bulk_action][value=team_membership]"
    assert_select "input[name=records][value=?]", line
    assert_select "input[name=reason][value=?]", "roster archaeology"
    assert_select "input[name=team_id][value=?]", @team.id.to_s
  end

  test "preview refuses an empty list" do
    post teams_positions_preview_bulk_membership_history_path, params: preview_params("   \n  ")

    assert_response :unprocessable_entity
    assert_match(/at least one callsign/i, flash[:error])
  end

  # ----------------------------------------------------------------- apply

  test "apply records the span against the chosen team" do
    assert_difference "PersonTeamLog.count", 1 do
      post teams_positions_bulk_membership_history_path,
           params: preview_params(line("2024-08-01", "2024-09-05"))
    end

    assert_response :unprocessable_entity
    history = PersonTeamLog.order(:id).last
    assert_equal @target.id, history.person_id
    assert_equal @team.id, history.team_id
    assert_equal Date.new(2024, 8, 1), history.joined_on
    assert_equal Date.new(2024, 9, 5), history.left_on

    assert_select "body", /applied to 1 person/
    # The list survives the apply so a correction does not mean re-typing it.
    assert_select "textarea[name=records]", text: line("2024-08-01", "2024-09-05")
  end

  test "apply leaves the leaving date empty when the line gave none" do
    post teams_positions_bulk_membership_history_path, params: preview_params(line)

    assert_nil PersonTeamLog.order(:id).last.left_on
  end

  test "a team manager may record history for the team they manage" do
    sign_in_as(@manager)

    assert_difference "PersonTeamLog.count", 1 do
      post teams_positions_bulk_membership_history_path, params: preview_params(line)
    end

    assert_equal @team.id, PersonTeamLog.order(:id).last.team_id
  end

  test "apply refuses a team outside the manageable set" do
    sign_in_as(@manager)

    assert_no_difference "PersonTeamLog.count" do
      post teams_positions_bulk_membership_history_path,
           params: preview_params(line, team: @other_team)
    end

    assert_response :unprocessable_entity
    assert_match(/choose a team/i, flash[:error])
  end

  test "apply writes nothing for a list of problems" do
    assert_no_difference "PersonTeamLog.count" do
      post teams_positions_bulk_membership_history_path,
           params: preview_params(@target.callsign)
    end

    assert_select "body", /Nothing was changed/
  end

  test "apply logs one commit row naming the action and every result" do
    post teams_positions_bulk_membership_history_path,
         params: preview_params(line, reason: "roster archaeology")

    log = ActionLog.where(event: "bulk-upload").last
    assert_equal "team_membership", log.data["action"]
    assert_equal "roster archaeology", log.data["reason"]
    assert_equal @target.callsign, log.data["results"].first["callsign"]
    assert_equal "success", log.data["results"].first["status"]
  end

  # ------------------------------------------------------------------ edit

  test "going back to edit keeps the list, the action and the team" do
    post teams_positions_edit_bulk_membership_history_path,
         params: preview_params(line, reason: "roster archaeology")

    assert_response :unprocessable_entity
    assert_select "textarea[name=records]", text: line
    assert_select "select[name=bulk_action] option[selected][value=team_membership]"
    assert_select "select[name=team_id] option[selected][value=?]", @team.id.to_s
    assert_select "input[name=reason][value=?]", "roster archaeology"
  end

  # ------------------------------------------------- several spells per person

  # A person can legitimately join, leave and rejoin the same team -- the
  # handler's own contract says so -- but the repeat check used to key on the
  # callsign alone and threw the second span away.
  test "two spells for one person both record" do
    assert_difference "PersonTeamLog.where(person_id: #{@target.id}).count", 2 do
      post teams_positions_bulk_membership_history_path,
           params: preview_params("#{@target.callsign},2019-08-01,2019-09-05\n" \
                                  "#{@target.callsign},2022-08-01,2022-09-05")
    end

    spans = PersonTeamLog.where(person_id: @target.id).order(:joined_on).pluck(:joined_on)
    assert_equal [Date.new(2019, 8, 1), Date.new(2022, 8, 1)], spans
  end

  test "the same span twice is still recorded once" do
    line = "#{@target.callsign},2019-08-01,2019-09-05"

    assert_difference "PersonTeamLog.where(person_id: #{@target.id}).count", 1 do
      post teams_positions_bulk_membership_history_path, params: preview_params("#{line}\n#{line}")
    end
  end
end
