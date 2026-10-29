# frozen_string_literal: true

require "test_helper"

class Person::MembershipHistoryControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include ReportCardTestHelper # assert_report_card / card_answer

  setup do
    Rails.cache.clear

    # Holds Council Cadre, Khaki Delegation and Mentor Cadre, and the Council
    # Manager, Khaki Supervisor and Mentor Team Manager positions (fixtures),
    # and no role at all.
    @target = person(:active_ranger)
    @no_history = person(:inactive_ranger)

    @admin = person(:auditor_ranger)
    # Holds a role in the broad PersonConcern gate that is neither Admin nor VC.
    @mentor = person(:ranger_with_custom_gender)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::MENTOR, "Mentor")
    grant_role(@admin, Role::ADMIN)
    grant_role(@mentor, Role::MENTOR)

    # No log fixtures exist; the history under test is built here.
    PersonTeamLog.create!(person_id: @target.id, team_id: teams(:council_cadre).id, joined_on: Date.new(2024, 3, 1))
    PersonTeamLog.create!(person_id: @target.id, team_id: teams(:green_dot_cadre).id,
                          joined_on: Date.new(2023, 1, 10), left_on: Date.new(2023, 9, 1))
    # Open, with no roster row: it ended on a day nothing recorded.
    PersonTeamLog.create!(person_id: @target.id, team_id: teams(:dirt_team).id, joined_on: Date.new(2024, 1, 5))
    PersonTeamLog.create!(person_id: @target.id, team_id: teams(:inactive_cadre).id,
                          joined_on: Date.new(2023, 2, 2), left_on: Date.new(2023, 3, 3))
    PersonPositionLog.create!(person_id: @target.id, position_id: positions(:council_manager).id,
                              joined_on: Date.new(2025, 3, 3))
    PersonPositionLog.create!(person_id: @target.id, position_id: positions(:ood_position).id,
                              joined_on: Date.new(2023, 5, 5), left_on: Date.new(2023, 6, 6))
  end

  teardown do
    Rails.cache.clear
  end

  test "admin sees both registers with recorded, pre-tracking and unrecorded dates" do
    sign_in_as(@admin)

    get person_membership_history_path(@target)

    assert_response :success
    assert_select "h1", text: /Teams & Positions History — #{@target.callsign}/
    assert_select "body", text: /3 current memberships and 3 past memberships, by team\./
    assert_select "body", text: /3 positions held and 1 revocation, by position\./

    assert_select "th", text: "Inactive Cadre (inactive)"
    assert_select "td", text: "Mar 1, 2024"
    assert_select "td", text: "Before Nov 29, 2022"
    assert_select "td", text: "Not recorded"
    assert_select "td", text: "Sep 1, 2023"
    assert_select "td", text: "Jun 6, 2023"
    assert_select "td", text: "Council Cadre" # the team that owns Council Manager
    assert_select "td", text: "—"
    assert_select "td", text: /^Left$/
    assert_select "td", text: /^Revoked$/
    assert_select "td", text: /^Member$/
    assert_select "td", text: /^Held$/

    assert_report_card
    assert_match(/without the date being written down/, card_answer("What does “Not recorded” mean?"))
  end

  test "a mentor sees it, as the Overview admits them" do
    sign_in_as(@mentor)

    get person_membership_history_path(@target)

    assert_response :success
    assert_select "h1", text: /Teams & Positions History/
  end

  test "a person without a person-page role is turned away" do
    sign_in_as(@target)

    get person_membership_history_path(@target)

    assert_redirected_to me_root_path
  end

  test "a person with nothing on record gets the empty state and no card" do
    sign_in_as(@admin)

    get person_membership_history_path(@no_history)

    assert_response :success
    assert_select "body",
                  text: /No team memberships or position grants are on record for #{@no_history.callsign}\. Teams and positions held before Nov 29, 2022 were never recorded here\./
    assert_report_card count: 0
    assert_select "table", count: 0
  end
end
