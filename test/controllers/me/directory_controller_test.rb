# frozen_string_literal: true

require "test_helper"

class Me::DirectoryControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include ExceptionRenderingTestHelper

  setup do
    @person = person(:active_ranger)
    sign_in_as(@person)
  end

  test "should get index" do
    get me_directory_url
    assert_response :success
  end

  test "requires authentication" do
    sign_out
    get me_directory_url
    assert_redirected_to root_path
  end

  test "DirectoryReport returns teams with members" do
    teams = DirectoryReport.execute
    assert teams.any?, "DirectoryReport should return teams with members"

    # All returned teams should have members
    teams.each do |team|
      assert team.members.any?, "Team #{team.title} should have members"

      team.members.each do |member|
        assert_not_nil member.person.id, "Member should have id"
        assert_not_nil member.person.callsign, "Member should have callsign"
      end
    end
  end

  test "DirectoryReport only includes active teams listed in the directory" do
    teams = DirectoryReport.execute
    assert teams.any?, "Should have teams"

    # Cadres and delegations by type, plus any team flagged include_in_directory
    teams.each do |team|
      team_record = Team.find(team.id)
      assert TeamManagement.directory_listed?(team_record),
             "Team #{team.title} should be a cadre/delegation or flagged for the directory"
      assert team_record.active?, "Team #{team.title} should be active"
    end
  end

  test "DirectoryReport places council cadre first when present" do
    teams = DirectoryReport.execute
    assert teams.any?, "Should have teams"

    # Council Cadre (id: 6) should be first if it exists
    council_team = teams.find { |t| t.id == Team::COUNCIL_CADRE }
    if council_team
      assert_equal Team::COUNCIL_CADRE, teams.first.id, "Council Cadre should appear first"
    end
  end

  test "displays team titles in response" do
    get me_directory_url
    assert_response :success

    # Get teams to verify they're displayed
    teams = DirectoryReport.execute
    assert teams.any?, "Should have teams to display"

    # Verify teams are displayed in the response
    teams.each do |team|
      assert_match team.title, response.body,
                   "Team #{team.title} should be displayed on page"
    end
  end

  test "displays member cards with callsigns" do
    get me_directory_url
    assert_response :success

    # Get teams and members to verify they're displayed
    teams = DirectoryReport.execute
    assert teams.any?, "Should have teams"

    # Check that member cards are rendered
    assert_select "div.rounded-lg", minimum: 1, message: "Should display member cards"

    # Verify specific member callsigns appear
    teams.each do |team|
      team.members.each do |member|
        assert_match member.person.callsign, response.body,
                     "Member #{member.person.callsign} should be displayed"
      end
    end
  end

  test "renders scroll navigation for teams" do
    get me_directory_url
    assert_response :success

    teams = DirectoryReport.execute
    assert teams.any?, "Should have teams for navigation"

    # Verify team anchor IDs are present for navigation
    teams.each do |team|
      assert_match "team-#{team.id}", response.body,
                   "Should have navigation anchor for #{team.title}"
    end
  end

  test "shows directory content in response body" do
    get me_directory_url
    assert_response :success
    # The response should contain directory-related content
    assert_match /Cadre Directory/, response.body
  end

  test "page contains expected content structure" do
    get me_directory_url
    assert_response :success

    # Should have description div
    assert_match /Contact information for Ranger Cadres, Delegations, and other listed teams/, response.body
  end

  test "returns 500 when DirectoryReport fails" do
    # Mock DirectoryReport to raise an error
    original_execute = DirectoryReport.method(:execute)

    DirectoryReport.define_singleton_method(:execute) do
      raise StandardError, "Database error"
    end

    begin
      with_exceptions_rendered do
        get me_directory_url

        # Should return 500 Internal Server Error
        assert_response :internal_server_error
      end
    ensure
      # Restore original method
      DirectoryReport.define_singleton_method(:execute, original_execute)
    end
  end
end
