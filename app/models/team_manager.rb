# frozen_string_literal: true

class TeamManager < ApplicationRecord
  self.table_name = "team_manager"

  # Associations
  belongs_to :team
  belongs_to :person

  # Find all team manager records for a person
  #
  # @param person_id [Integer]
  # @return [ActiveRecord::Relation]
  def self.find_for_person(person_id)
    where(person_id: person_id)
  end

  # Find a team for a given person
  #
  # @param team_id [Integer]
  # @param person_id [Integer]
  # @return [TeamManager, nil]
  def self.find_team_for_person(team_id, person_id)
    find_by(team_id: team_id, person_id: person_id)
  end

  # Can the person manage this position?
  #
  # @param person_id [Integer]
  # @param position_id [Integer]
  # @return [Boolean]
  # Which of these positions belong to a team this person manages. One question
  # asked once, rather than one round trip per position.
  #
  # @param person_id [Integer]
  # @param position_ids [Array<Integer>]
  # @return [Array<Integer>]
  def self.manageable_position_ids(person_id, position_ids)
    return [] if position_ids.blank?

    joins("INNER JOIN position ON position.team_id = team_manager.team_id")
      .where("team_manager.person_id": person_id)
      .where("position.id": position_ids)
      .distinct
      .pluck(Arel.sql("position.id"))
  end

  def self.can_manage_position?(person_id, position_id)
    joins("INNER JOIN position ON position.team_id = team_manager.team_id")
      .where("team_manager.person_id": person_id)
      .where("position.id": position_id)
      .exists?
  end

  # Retrieve the teams a person is a manager of
  #
  # @param person_id [Integer]
  # @return [Array<Hash>]
  def self.retrieve_teams_for_person(person_id)
    where(person_id: person_id)
      .includes(:team)
      .map do |record|
      {
        id: record.team_id,
        title: record.team.title
      }
    end
  end

  # Retrieve the team ids for a person
  #
  # @param person_id [Integer]
  # @return [Array<Integer>]
  def self.retrieve_team_ids_for_person(person_id)
    where(person_id: person_id).pluck(:team_id)
  end

  # Add a team manager
  #
  # @param team_id [Integer]
  # @param person_id [Integer]
  # @param reason [String, nil]
  # @return [void]
  def self.add_person(team_id, person_id, reason = nil)
    return if exists?(team_id: team_id, person_id: person_id)

    create!(team_id: team_id, person_id: person_id)
    ActionLog.record(Current.person, "team-manager-add", reason, { team_id: team_id }, person_id)
  end

  # Remove a team manager
  #
  # @param team_id [Integer]
  # @param person_id [Integer]
  # @param reason [String, nil]
  # @return [void]
  def self.remove_person(team_id, person_id, reason = nil)
    record = find_by(team_id: team_id, person_id: person_id)
    return unless record

    record.destroy
    ActionLog.record(Current.person, "team-manager-remove", reason, { team_id: team_id }, person_id)
  end

  # Is the person a manager for a given team?
  #
  # @param team_id [Integer]
  # @param person_id [Integer]
  # @return [Boolean]
  def self.manager?(team_id, person_id)
    exists?(team_id:, person_id:)
  end

  # Is the person a manager of any team?
  #
  # @param person_id [Integer]
  # @return [Boolean]
  def self.manager_of_any?(person_id)
    exists?(person_id:)
  end
end
