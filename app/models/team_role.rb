# frozen_string_literal: true

class TeamRole < ApplicationRecord
  self.table_name = "team_role"
  self.primary_key = [:team_id, :role_id]

  belongs_to :team
  belongs_to :role

  class << self
    # Find all roles for a given team
    def find_all_for_team(team_id)
      where(team_id:)
    end

    # Find all the teams with granted roles for a person
    def find_roles_for_person(person_id)
      PersonTeam
        .select("team.id", "team.title", "team_role.role_id")
        .where(person_id:)
        .joins(team: :team_roles)
    end

    # Add a role association to a team
    def add(team_id, role_id, reason = nil)
      return if exists?(team_id:, role_id:)

      create!(team_id:, role_id:)
      Rails.cache.clear
      ActionLog.record(Current.person, "team-role-add", reason, { team_id:, role_id: })
    end

    # Remove a role association from a team
    def remove(team_id, role_id, reason = nil)
      where(team_id:, role_id:).delete_all
      Rails.cache.clear
      ActionLog.record(Current.person, "team-role-remove", reason, { team_id:, role_id: })
    end
  end
end
