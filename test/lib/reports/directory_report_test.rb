# frozen_string_literal: true

require "test_helper"

class DirectoryReportTest < ActiveSupport::TestCase
  test "execute returns an array" do
    result = DirectoryReport.execute
    assert_kind_of Array, result
  end

  test "execute_returns_array_of_OpenStruct_objects" do
    result = DirectoryReport.execute
    assert result.any?, "DirectoryReport should return teams with members"
    assert_kind_of DirectoryReport::TeamDirectory, result.first
    assert_respond_to result.first, :id
    assert_respond_to result.first, :title
    assert_respond_to result.first, :members
  end

  test "team objects have required attributes" do
    result = DirectoryReport.execute
    assert result.any?, "DirectoryReport should return teams"

    team = result.first
    assert_respond_to team, :id
    assert_respond_to team, :title
    assert_respond_to team, :email
    assert_respond_to team, :description
    assert_respond_to team, :members
  end

  test "member objects have required attributes" do
    result = DirectoryReport.execute
    assert result.any?, "DirectoryReport should return teams"

    team = result.first
    assert team.members.any?, "Team should have members"

    member = team.members.first
    assert_respond_to member, :person
    assert_respond_to member.person, :callsign
    assert_respond_to member, :overseer_positions
  end

  test "filters only active teams" do
    # This test verifies the query logic returns only active teams
    result = DirectoryReport.execute
    assert result.any?, "DirectoryReport should return teams"

    # All teams in result should be active
    result.each do |team_data|
      team = Team.find(team_data.id)
      assert team.active, "Team #{team.title} should be active"
    end
  end

  test "lists Cadres and Delegations plus any team flagged for the directory" do
    result = DirectoryReport.execute
    assert result.any?, "DirectoryReport should return teams"

    result.each do |team_data|
      team = Team.find(team_data.id)
      assert TeamManagement.directory_listed?(team),
             "Team #{team.title} is neither a cadre/delegation nor flagged for the directory"
      assert team.active
    end
  end

  # include_in_directory is the Team Records checkbox. Without this branch it
  # does nothing, so the flag needs coverage in both directions.
  test "includes a plain team flagged for the directory and excludes an unflagged one" do
    listed = teams(:dirt_team)
    listed.update!(type: Team::TYPE_TEAM, active: true, include_in_directory: true)
    PersonTeam.create!(team_id: listed.id, person_id: person(:active_ranger).id)

    unlisted = teams(:operations_team)
    unlisted.update!(type: Team::TYPE_TEAM, active: true, include_in_directory: false)
    PersonTeam.create!(team_id: unlisted.id, person_id: person(:active_ranger).id)

    ids = DirectoryReport.execute.map(&:id)

    assert_includes ids, listed.id
    assert_not_includes ids, unlisted.id
  end

  test "handles members with no photos" do
    result = DirectoryReport.execute
    assert result.any?, "DirectoryReport should return teams"

    # Members can have nil avatar_photo - this should be handled gracefully
    result.each do |team|
      assert team.members.any?, "Team should have members"
      team.members.each do |member|
        # avatar_photo_attachment can be nil - accessing it should not raise
        assert_nothing_raised { member.person.avatar_photo_attachment }
      end
    end
  end

  test "overseer positions are filtered by manager and supervisor titles" do
    # This test verifies that only positions with "manager" or "supervisor" in the title
    # are included in overseer_positions
    result = DirectoryReport.execute
    assert result.any?, "DirectoryReport should return teams"

    result.each do |team|
      assert team.members.any?, "Team should have members"
      team.members.each do |member|
        if member.overseer_positions&.any?
          member.overseer_positions.each do |position|
            title_lower = position.title.downcase
            has_manager_or_supervisor = title_lower.include?("manager") || title_lower.include?("supervisor")
            assert has_manager_or_supervisor,
                   "Overseer position '#{position.title}' should contain 'manager' or 'supervisor'"
          end
        end
      end
    end

    # Note: Not all members will have overseer positions, this test validates
    # that when they exist, they have the correct title pattern
  end

  test "overseer positions belong to the team" do
    # Verify that overseer positions are from the correct team
    result = DirectoryReport.execute
    assert result.any?, "DirectoryReport should return teams"

    result.each do |team_data|
      assert team_data.members.any?, "Team should have members"
      team_data.members.each do |member|
        if member.overseer_positions&.any?
          member.overseer_positions.each do |position|
            actual_position = Position.find(position.id)
            assert_equal team_data.id, actual_position.team_id,
                         "Overseer position should belong to team #{team_data.title}"
          end
        end
      end
    end

    # Note: Not all members will have overseer positions, this test validates
    # that when they exist, they belong to the correct team
  end
end
