# frozen_string_literal: true

require "test_helper"

# .reconstruct_awards is the live code path. The entry points (.rebuild_all and
# .rebuild_for_person_id) are deliberate no-ops -- their bodies are commented out
# upstream, matching production Laravel -- so there is nothing there to test yet.
class AwardManagementTest < ActiveSupport::TestCase
  setup do
    @person = person(:active_ranger)
    # awards_auto_grant + awards_grants_service_year + awards_eligible.
    @team = teams(:dirt_team)
  end

  # Walk the person through reconstruction off their team logs alone: no auto-granting
  # positions, so no trainer records and no timesheets to consider.
  def reconstruct(save_person: false)
    AwardManagement.reconstruct_awards(
      @person,
      PersonAward.where(person_id: @person.id).to_a,
      nil,
      nil,
      AwardManagement.retrieve_team_logs(@person.id),
      nil,
      save_person: save_person
    )
  end

  def log_team_membership(joined_on:, left_on: nil)
    PersonTeamLog.create!(person: @person, team: @team, joined_on: joined_on, left_on: left_on)
  end

  test "a team log grants an award for each year of membership that is missing one" do
    # The person already holds a DIRT award for 2022 (fixture :dirt_2022) but not 2023.
    log_team_membership(joined_on: Date.new(2022, 6, 1), left_on: Date.new(2023, 9, 1))

    assert_difference -> { PersonAward.where(person_id: @person.id, team_id: @team.id).count }, 1 do
      reconstruct
    end

    granted = PersonAward.find_by(person_id: @person.id, team_id: @team.id, year: 2023)

    assert_equal "automatic creation", granted.notes
    assert granted.awards_grants_service_year, "should inherit the team's awards_grants_service_year"
  end

  test "a year already awarded is not granted twice" do
    log_team_membership(joined_on: Date.new(2022, 6, 1), left_on: Date.new(2022, 9, 1))

    assert_no_difference -> { PersonAward.where(person_id: @person.id, team_id: @team.id).count } do
      reconstruct
    end

    assert_equal 1, PersonAward.where(person_id: @person.id, team_id: @team.id, year: 2022).count
  end

  test "an open ended team log grants awards through the current year" do
    log_team_membership(joined_on: Date.new(2022, 6, 1))

    reconstruct

    years = PersonAward.where(person_id: @person.id, team_id: @team.id).pluck(:year)

    assert_equal((2022..Current.year).to_a, years.sort)
  end

  test "years_of_awards collects the team years alongside the special award years" do
    log_team_membership(joined_on: Date.new(2022, 6, 1), left_on: Date.new(2023, 9, 1))

    reconstruct

    # 2020 and 2022 come from the person's special awards (:special_service_2020,
    # :volunteer_2022); 2022 and 2023 from the team log.
    assert_equal [2020, 2022, 2023], @person.years_of_awards
  end

  test "only teams which auto grant awards are considered" do
    # The person holds Khaki awards, but Khaki does not auto grant.
    refute teams(:khaki_team).awards_auto_grant

    PersonTeamLog.create!(person: @person, team: teams(:khaki_team), joined_on: Date.new(2022, 6, 1))

    assert_empty AwardManagement.retrieve_team_logs(@person.id)
  end
end
