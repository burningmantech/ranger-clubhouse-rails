# frozen_string_literal: true

# Membership - Support library for managing person memberships to teams and positions
#
# This class provides methods for:
# - Retrieving team and position memberships for a person
# - Updating position grants and revocations with authorization checks
# - Updating team memberships with authorization checks
# - Managing team manager assignments
# - Managing roles for positions and teams
class Membership
  # MembershipInfo - Result object containing membership data for a person
  class MembershipInfo
    attr_accessor :teams, :management, :not_member_teams, :positions

    def initialize
      @teams = []
      @management = []
      @not_member_teams = []
      @positions = []
    end
  end

  # Retrieve the assigned teams and positions for a given person
  #
  # @param person [Person] the person to retrieve membership information for
  # @return [MembershipInfo] object containing teams, management, not_member_teams, and positions
  def self.retrieve_for_person(person)
    person_id = person.id
    info = MembershipInfo.new

    info.teams = PersonTeam.find_all_teams_for_person(person_id)
    info.positions = PersonPosition.retrieve_all_for_person(person)
    info
  end

  # Grant and/or revoke positions for a person.
  #
  # - For general positions (not associated with a team, usually basic dirt) the user must
  #   hold the VC or Mentor roles
  # - For team positions, the user must be a team administrator for the team the position belongs to.
  #
  # @param user_id [Integer] the user performing the action
  # @param person [Person] the person to update positions for
  # @param position_ids [Array<Integer>, nil] complete list of position IDs to set (determines grants/revokes);
  #   empty revokes every position the user can manage, nil leaves them alone
  # @param grant_ids [Array<Integer>, nil] specific position IDs to grant
  # @param revoke_ids [Array<Integer>, nil] specific position IDs to revoke
  # @param reason [String] reason for the change
  # @param is_admin [Boolean] whether the user is an admin (bypasses team manager checks)
  def self.update_positions_for_person(user_id:, person:, position_ids: nil,
                                       grant_ids: nil, revoke_ids: nil,
                                       reason:, is_admin:)
    person_id = person.id
    positions = PersonPosition.retrieve_all_for_person(person)

    manage_ids = is_admin ? nil : TeamManager.retrieve_team_ids_for_person(user_id)

    new_ids = []
    delete_ids = []

    unless position_ids.nil?
      new_ids, delete_ids = determine_grant_revokes(positions, position_ids, :id)
      unless is_admin
        # Need to check on each position to see if it's allowed
        new_ids = can_manage_positions(new_ids, manage_ids)
        delete_ids = can_manage_positions(delete_ids, manage_ids)
      end
    end

    if grant_ids.present?
      grant_ids = can_manage_positions(grant_ids, manage_ids) unless is_admin
      new_ids = new_ids + grant_ids
    end

    if revoke_ids.present?
      revoke_ids = can_manage_positions(revoke_ids, manage_ids) unless is_admin
      delete_ids = delete_ids + revoke_ids
    end

    # Mass revoke the old positions
    PersonPosition.remove_ids_from_person(person_id, delete_ids, reason) if delete_ids.present?

    # Mass grant new positions
    PersonPosition.add_ids_to_person(person_id, new_ids, reason) if new_ids.present?

    PersonRole.clear_cache(person_id)
  end

  # Check to see if the user can grant or revoke various positions for a person.
  #
  # @param ids [Array<Integer>] position IDs to check
  # @param manage_ids [Array<Integer>] team IDs the user can manage
  # @return [Array<Integer>] filtered position IDs that can be managed
  def self.can_manage_positions(ids, manage_ids)
    return [] if ids.blank?

    Position.where(id: ids).where(team_id: manage_ids).pluck(:id)
  end

  # Determine which IDs are to be added and deleted based on what IDs are currently granted.
  #
  # @param groups [Array] current collection of objects
  # @param group_ids [Array<Integer>] desired IDs
  # @param key [Symbol] attribute name to extract ID from
  # @return [Array<Array<Integer>>] [new_ids, delete_ids]
  def self.determine_grant_revokes(groups, group_ids, key)
    current_ids = groups.map { |g| g.public_send(key) }
    new_ids = group_ids - current_ids
    delete_ids = current_ids - group_ids
    [new_ids, delete_ids]
  end

  # Grant and/or revoke teams for a person.
  #
  # @param user_id [Integer] the user performing the action
  # @param person_id [Integer] the person to update teams for
  # @param team_ids [Array<Integer>, nil] complete list of team IDs to set (determines grants/revokes);
  #   empty removes every team the user can manage, nil leaves them alone
  # @param grant_ids [Array<Integer>, nil] specific team IDs to grant
  # @param revoke_ids [Array<Integer>, nil] specific team IDs to revoke
  # @param reason [String] reason for the change
  # @param is_admin [Boolean] whether the user is an admin (bypasses team manager checks)
  def self.update_teams_for_person(user_id:, person_id:, team_ids: nil,
                                   grant_ids: nil, revoke_ids: nil,
                                   reason:, is_admin:)
    memberships = PersonTeam.find_all_teams_for_person(person_id)

    new_ids = []
    delete_ids = []

    manage_ids = is_admin ? nil : TeamManager.retrieve_team_ids_for_person(user_id)

    unless team_ids.nil?
      new_ids, delete_ids = determine_grant_revokes(memberships, team_ids, :id)

      unless is_admin
        new_ids = can_manage_team(new_ids, manage_ids)
        delete_ids = can_manage_team(delete_ids, manage_ids)
      end
    end

    if grant_ids.present?
      grant_ids = can_manage_team(grant_ids, manage_ids) unless is_admin
      new_ids = new_ids + grant_ids
    end

    if revoke_ids.present?
      revoke_ids = can_manage_team(revoke_ids, manage_ids) unless is_admin
      delete_ids = delete_ids + revoke_ids
    end

    delete_ids.each do |id|
      PersonTeam.remove_person(id, person_id, reason)
    end

    new_ids.each do |id|
      PersonTeam.add_person(id, person_id, reason)
    end

    PersonRole.clear_cache(person_id)
  end

  # Update the team(s) management for a person
  #
  # @param user_id [Integer] the user performing the action
  # @param person_id [Integer] the person to update management for
  # @param team_ids [Array<Integer>, nil] team IDs to set as managed by person; nil leaves them alone
  # @param reason [String] reason for the change
  # @param is_admin [Boolean] whether the user is an admin (bypasses team manager checks)
  def self.update_management_for_person(user_id:, person_id:, team_ids:,
                                        reason:, is_admin:)
    return if team_ids.nil?

    memberships = TeamManager.find_for_person(person_id)

    new_ids, delete_ids = determine_grant_revokes(memberships, team_ids, :team_id)

    unless is_admin
      # Need to check on each team to see if it's allowed
      manage_ids = TeamManager.retrieve_team_ids_for_person(user_id)

      new_ids = can_manage_team(new_ids, manage_ids)
      delete_ids = can_manage_team(delete_ids, manage_ids)
    end

    delete_ids.each do |id|
      TeamManager.remove_person(id, person_id, reason)
    end

    new_ids.each do |id|
      TeamManager.add_person(id, person_id, reason)
    end

    PersonRole.clear_cache(person_id)
  end

  # Can the person manage teams?
  #
  # @param ids [Array<Integer>] team IDs to check
  # @param manage_ids [Array<Integer>] team IDs the user can manage
  # @return [Array<Integer>] filtered team IDs that can be managed
  def self.can_manage_team(ids, manage_ids)
    ids & manage_ids
  end

  # Grant and/or revoke roles for a position.
  #
  # @param position_id [Integer] the position to update roles for
  # @param role_ids [Array<Integer>] role IDs to associate with the position
  # @param reason [String] reason for the change
  def self.update_position_roles(position_id, role_ids, reason)
    existing_roles = PositionRole.find_all_for_position(position_id)
    existing_roles_by_id = existing_roles.index_by(&:role_id)

    # Find the IDs to add
    role_ids.each do |id|
      PositionRole.add(position_id, id, reason) unless existing_roles_by_id.key?(id)
    end

    # Find the IDs to delete
    existing_roles.each do |existing|
      PositionRole.remove(position_id, existing.role_id, reason) unless role_ids.include?(existing.role_id)
    end
  end

  # Grant and/or revoke roles for a team.
  #
  # @param team_id [Integer] the team to update roles for
  # @param role_ids [Array<Integer>] role IDs to associate with the team
  # @param reason [String] reason for the change
  def self.update_team_roles(team_id, role_ids, reason)
    existing_roles = TeamRole.find_all_for_team(team_id)
    existing_roles_by_id = existing_roles.index_by(&:role_id)

    # Find the IDs to add
    role_ids.each do |id|
      TeamRole.add(team_id, id, reason) unless existing_roles_by_id.key?(id)
    end

    # Find the IDs to delete
    existing_roles.each do |existing|
      TeamRole.remove(team_id, existing.role_id, reason) unless role_ids.include?(existing.role_id)
    end
  end
end
