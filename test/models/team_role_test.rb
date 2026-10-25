# frozen_string_literal: true

require "test_helper"

class TeamRoleTest < ActiveSupport::TestCase
  setup do
    @person = person(:active_ranger)
    @team = teams(:mentor_cadre)
    @role = Role.find_or_create_by!(id: Role::TRAINER) { |r| r.title = "Trainer" }

    TeamRole.find_or_create_by!(team_id: @team.id, role_id: @role.id)
  end

  test "find_roles_for_person returns the roles granted through team membership" do
    PersonTeam.find_or_create_by!(person_id: @person.id, team_id: @team.id)

    rows = TeamRole.find_roles_for_person(@person.id)

    assert_equal [[@team.title, @role.id]], rows.map { |r| [r.title, r.role_id] }
  end

  test "find_roles_for_person is empty for a person with no teams" do
    PersonTeam.where(person_id: @person.id).delete_all

    assert_empty TeamRole.find_roles_for_person(@person.id)
  end
end
