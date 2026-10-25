# frozen_string_literal: true

class PersonTeam < ApplicationRecord
  self.table_name = "person_team"
  self.primary_key = [:person_id, :team_id]

  belongs_to :person
  belongs_to :team

  # The roles a membership grants are the team's (TeamRole, by team_id;
  # RoleManager reads them there), so a membership owns none: a has_many
  # through a person_team_id the team_role table never had made every
  # destroy raise.

  # Callbacks
  after_save :rebuild_awards
  after_destroy :rebuild_awards

  # Find all team memberships for the person
  def self.find_all_teams_for_person(person_id)
    rows = Team.select("team.*",
                Position.where("team.id = position.team_id")
                        .select(1)
                        .arel
                        .exists
                        .as("has_positions"),
                TeamManager.where("team.id = team_manager.team_id")
                           .where(team_manager: { person_id: })
                           .select(1)
                           .arel
                           .exists
                           .as("is_manager")
    ).joins(:person_team)
        .where(person_team: { person_id: })
        .order(:title)
    # case integers to boolean
    # rows.each do |row|
    # row.has_positions = row.has_positions.positive?
    # row.is_manager = row.is_manager.positive?
    # end

    rows
  end

  # Retrieve all Cadre/Delegation membership team ids for a given person
  def self.retrieve_cadre_membership_ids(person_id)
    Team.cadres_and_delegations_of(person_id).pluck(:id)
  end

  # Find all teams with MVR eligible for the person
  def self.retrieve_mvr_eligible_for_person(person_id)
    Team.select(:id, :title)
        .joins(:person_team)
        .where(person_team: { person_id: person_id })
        .where(active: true)
        .where(mvr_eligible: true)
        .order(:title)
  end

  # Find all teams with PVR eligible for the person
  def self.retrieve_pvr_eligible_for_person(person_id)
    Team.select(:id, :title)
        .joins(:person_team)
        .where(person_team: { person_id: person_id })
        .where(active: true)
        .where(pvr_eligible: true)
        .order(:title)
  end

  # Is the person a member of a MVR eligible team?
  def self.have_mvr_eligible_for_person(person_id)
    Team.joins(:person_team)
        .where(person_team: { person_id: person_id })
        .where(active: true)
        .where(mvr_eligible: true)
        .exists?
  end

  # Is the person a member of a PVR eligible team?
  def self.have_pvr_eligible_team(person_id)
    Team.joins(:person_team)
        .where(person_team: { person_id: person_id })
        .where(active: true)
        .where(pvr_eligible: true)
        .exists?
  end

  # Is the person a team member?
  def self.have_team(team_id, person_id)
    exists?(team_id: team_id, person_id: person_id)
  end

  # Find a membership record for the person and team
  def self.retrieve_for_person(team_id, person_id)
    find_by(person_id: person_id, team_id: team_id)
  end

  # Add a person to a team. Log the addition.
  def self.add_person(team_id, person_id, reason = nil)
    has_tech_ninja = TeamRole.exists?(team_id: team_id, role_id: Role::TECH_NINJA)
    if has_tech_ninja && !Current.person&.has_role?(Role::TECH_NINJA)
      raise AuthorizationError, "No authorization to grant membership for a team with the Tech Ninja permission associated."
    end

    has_admin = TeamRole.exists?(team_id: team_id, role_id: Role::ADMIN)
    if has_admin && !Current.person&.has_role?(Role::ADMIN)
      raise AuthorizationError, "No authorization to grant membership for a team with the Admin permission associated."
    end

    create!(team_id: team_id, person_id: person_id)
    PersonTeamLog.add_person(team_id, person_id)
    ActionLog.record(Current.person, "person-team-add", reason, { team_id: team_id }, person_id)
    # Team membership carries team_role grants into the cached role set.
    RoleManager.purge_person(person_id)
  end

  # Remove a person from a team
  def self.remove_person(team_id, person_id, reason)
    where(team_id: team_id, person_id: person_id).delete_all
    PersonTeamLog.remove_person(team_id, person_id)
    ActionLog.record(Current.person, "person-team-remove", reason, { team_id: team_id }, person_id)
    RoleManager.purge_person(person_id)
  end

  # Remove all teams for a person
  def self.remove_all_from_person(person_id, reason)
    teams = find_all_teams_for_person(person_id)

    teams.each do |team|
      remove_person(team.id, person_id, reason)
    end
  end

  private

  def rebuild_awards
    AwardManagement.rebuild_for_person_id(person_id)
  end
end
