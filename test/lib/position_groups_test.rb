# frozen_string_literal: true

require "test_helper"

class PositionGroupsTest < ActiveSupport::TestCase
  test "teamless positions come first as General Positions, then each team's by title" do
    zulu = Team.new(id: 1, title: "Zulu")
    alpha = Team.new(id: 2, title: "alpha")
    positions = [Position.new(title: "Z1", team: zulu),
                 Position.new(title: "A1", team: alpha),
                 Position.new(title: "G1"),
                 Position.new(title: "G2", team_id: Team.maximum(:id).to_i + 1),
                 Position.new(title: "A2", team: alpha)]

    groups = PositionGroups.by_team(positions).map { |title, list| [title, list.map(&:title)] }
    assert_equal [["General Positions", %w[G1 G2]], ["alpha", %w[A1 A2]], ["Zulu", %w[Z1]]], groups

    assert_equal %w[alpha Zulu], PositionGroups.by_team(positions.first(2)).map(&:first)
  end

  test "positions and their teams load once each, and loaded teams are not fetched again" do
    positions = Position.where.not(team_id: nil)

    assert_queries_count(2) { PositionGroups.by_team(positions) }
    assert_no_queries { PositionGroups.by_team(positions) }
  end
end
