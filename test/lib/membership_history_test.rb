# frozen_string_literal: true

require "test_helper"

class MembershipHistoryTest < ActiveSupport::TestCase
  BACKFILL = MembershipHistory::TRACKING_BEGAN

  # active_ranger holds Council Cadre, Khaki Delegation and Mentor Cadre, and
  # Council Manager, Khaki Supervisor and Mentor Team Manager (fixtures). No
  # log fixtures exist; each test writes the rows it reads.
  setup do
    @person = person(:active_ranger)
  end

  test "teams: dated, before the records, closed rows only, past, stale, duplicate and inactive" do
    council = teams(:council_cadre)
    team_log(council, "2024-03-01")
    team_log(council, "2022-11-29")                               # the backfill row, left open beside the real join
    team_log(teams(:mentor_cadre), "2022-11-29", "2024-06-14")    # closed while the roster row survived
    team_log(teams(:green_dot_cadre), "2023-01-10", "2023-09-01") # a past membership
    team_log(teams(:green_dot_cadre), "2024-01-05")               # stale: open, with no roster row
    team_log(teams(:dirt_team), "2022-11-29")
    team_log(teams(:dirt_team), "2022-11-29")                     # the same row twice
    team_log(teams(:inactive_cadre), "2023-02-02", "2023-03-03")
    team_log(teams(:operations_team), "2015-03-01", "2018-05-01")  # recorded through Bulk Membership History

    spells = MembershipHistory.new(@person).teams

    assert_equal ["Council Cadre", "Council Cadre", "DIRT Team", "Green Dot Cadre", "Green Dot Cadre",
                  "Inactive Cadre", "Khaki Delegation", "Mentor Cadre", "Mentor Cadre", "Operations"],
                 spells.map(&:title)
    council_backfill, council_now, dirt, green_dot_past, green_dot_stale, inactive, khaki, mentor_past, mentor_now,
      operations = spells

    assert_spell council_backfill, began_on: BACKFILL, ended_on: nil, current: false
    assert_predicate council_backfill, :before_tracking?
    assert_spell council_now, began_on: Date.new(2024, 3, 1), ended_on: nil, current: true
    assert_not_predicate council_now, :before_tracking?
    assert_spell dirt, began_on: BACKFILL, ended_on: nil, current: false
    assert_spell green_dot_past, began_on: Date.new(2023, 1, 10), ended_on: Date.new(2023, 9, 1), current: false
    assert_spell green_dot_stale, began_on: Date.new(2024, 1, 5), ended_on: nil, current: false
    assert_spell inactive, active: false, ended_on: Date.new(2023, 3, 3)
    assert_spell khaki, began_on: BACKFILL, ended_on: nil, current: true, active: true
    assert_predicate khaki, :before_tracking?
    assert_spell mentor_past, began_on: BACKFILL, ended_on: Date.new(2024, 6, 14), current: false
    assert_spell mentor_now, began_on: nil, ended_on: nil, current: true
    assert_not_predicate mentor_now, :before_tracking?
    assert_spell operations, began_on: Date.new(2015, 3, 1), ended_on: Date.new(2018, 5, 1), current: false
    assert_not_predicate operations, :before_tracking?
    assert spells.all? { |spell| spell.team_title.nil? }
  end

  test "positions: two spells, a same-day spell, the owning team, a team-less and a deleted position" do
    manager = positions(:council_manager)
    position_log(manager, "2023-03-01", "2024-02-10")
    position_log(manager, "2025-03-03")
    position_log(positions(:mentor_manager), "2024-04-17", "2024-04-17") # granted and revoked the same day
    position_log(positions(:mentor_manager), "2024-05-01")
    position_log(positions(:training_lead), "2024-02-02")               # stale, and owned by no team
    position_log(positions(:ood_position), "2023-05-05", "2023-06-06")
    # A deleted position keeps its log rows; insert skips the belongs_to check.
    PersonPositionLog.insert({ person_id: @person.id, position_id: 999_999,
                               joined_on: Date.new(2023, 7, 7), left_on: Date.new(2023, 8, 8) })

    spells = MembershipHistory.new(@person).positions

    assert_equal ["Council Manager", "Council Manager", "Khaki Supervisor", "Mentor Team Manager",
                  "Mentor Team Manager", "OOD (Officer of the Day)", "Position #999999", "Training Lead"],
                 spells.map(&:title)
    manager_past, manager_now, khaki, mentor_same_day, mentor_now, ood, deleted, training_lead = spells

    assert_spell manager_past, team_title: "Council Cadre", began_on: Date.new(2023, 3, 1),
                               ended_on: Date.new(2024, 2, 10), current: false
    assert_spell manager_now, began_on: Date.new(2025, 3, 3), ended_on: nil, current: true
    assert_spell khaki, team_title: "Khaki Delegation", began_on: BACKFILL, current: true
    assert_spell mentor_same_day, began_on: Date.new(2024, 4, 17), ended_on: Date.new(2024, 4, 17), current: false
    assert_spell mentor_now, began_on: Date.new(2024, 5, 1), current: true
    assert_spell ood, team_title: nil, began_on: Date.new(2023, 5, 5), ended_on: Date.new(2023, 6, 6), current: false
    assert_spell deleted, team_title: nil, active: true, ended_on: Date.new(2023, 8, 8), current: false
    assert_spell training_lead, team_title: nil, began_on: Date.new(2024, 2, 2), ended_on: nil, current: false
  end

  test "titles sort without regard to case" do
    team_log(Team.create!(title: "SITE Team", type: Team::TYPE_TEAM, active: true), "2024-01-01")
    team_log(Team.create!(title: "Sandman Team", type: Team::TYPE_TEAM, active: true), "2024-01-01")

    titles = MembershipHistory.new(@person).teams.map(&:title)

    assert_equal ["Council Cadre", "Khaki Delegation", "Mentor Cadre", "Sandman Team", "SITE Team"], titles
  end

  test "a person with nothing held and nothing logged has no spells" do
    history = MembershipHistory.new(person(:inactive_ranger))

    assert_empty history.teams
    assert_empty history.positions
  end

  test "reads each log, the roster and the titles once per kind" do
    assert_queries_count(6) { MembershipHistory.new(@person) }
  end

  private

  def team_log(team, joined_on, left_on = nil)
    PersonTeamLog.create!(person_id: @person.id, team_id: team.id, joined_on:, left_on:)
  end

  def position_log(position, joined_on, left_on = nil)
    PersonPositionLog.create!(person_id: @person.id, position_id: position.id, joined_on:, left_on:)
  end

  def assert_spell(spell, **expected)
    assert_equal expected, spell.to_h.slice(*expected.keys), spell.title
  end
end
