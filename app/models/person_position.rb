# frozen_string_literal: true

# Custom error for authorization failures in position grants
class AuthorizationError < StandardError; end

# PersonPosition represents the many-to-many relationship between Person and Position.
# A person can hold multiple positions, and a position can be held by multiple people.
# This model includes methods for managing position grants, checking position holdings,
# and logging position changes.
class PersonPosition < ApplicationRecord
  self.table_name = "person_position"

  belongs_to :person
  belongs_to :position

  # Check if a person holds one or more positions
  def self.have_position?(person_id, position_id)
    where(person_id: person_id, position_id: position_id).exists?
  end

  # Find the training positions a person holds that matter: the base Training
  # position (always) plus each ART some other position requires -- with
  # exclude_potentials, one of those requiring positions must be held as well.
  def self.find_training_positions(person_id, exclude_potentials = false)
    # The subquery aliases position as `tp` so `position.id` refers to the OUTER
    # row; un-aliased it compared each inner row to itself and never matched.
    requiring = Position.from("position tp").where("tp.training_position_id = position.id")
    if exclude_potentials
      requiring = requiring.joins("JOIN person_position pp ON pp.position_id = tp.id").where(pp: { person_id: })
    end

    Position.where(type: Position::TYPE_TRAINING)
            .joins(:person_position)
            .where(person_position: { person_id: })
            .where("position.id = :training_id OR EXISTS (:requiring)",
                   training_id: Position::TRAINING, requiring: requiring.select(1).limit(1))
            .order(:title)
            .sort_by(&:title)
  end

  # Find people who are granted a specific position
  def self.retrieve_grants(position_id)
    Person
      .joins(:person_position)
      .where(person_position: { position_id: position_id })
      .order(:callsign)
      .pluck(:id, :callsign)
      .map { |id, callsign| { id: id, callsign: callsign } }
  end

  # Find all held positions for a person
  def self.retrieve_all_for_person(person, include_past_grants: false,
                                   include_eligibility: false,
                                   exclude_trainee_positions: false)
    rows = build_position_scope(person.id, exclude_trainee_positions)

    if include_past_grants
      past_grants = build_past_grants_scope(person.id, exclude_trainee_positions)
      rows = (rows + past_grants).uniq(&:id)
    end

    rows = rows.sort_by(&:title)
    rows.each { |row| row.blockers = SignInBlocker.check(person, row) } if include_eligibility
    rows
  end

  # Remove all positions from a person in response to status change
  def self.reset_positions(person_id, reason, action)
    remove_ids = where(person_id: person_id).pluck(:position_id)

    if action == Person::ADD_NEW_USER
      add_ids = []
      eligible_ids = Position.where(active: true, new_user_eligible: true).pluck(:id)

      eligible_ids.each do |position_id|
        remove_ids.include?(position_id) ? remove_ids.delete(position_id) : add_ids << position_id
      end

      add_ids_to_person(person_id, add_ids, reason)
    end

    remove_ids_from_person(person_id, remove_ids, reason)
  end

  # Add positions to a person. Log the action.
  # @raise [AuthorizationError] if user lacks permission to grant position
  def self.add_ids_to_person(person_id, ids, reason)
    added_ids = []

    ids.each do |id|
      validate_position_grant_authorization!(id)
      next if exists?(person_id: person_id, position_id: id)

      create!(person_id: person_id, position_id: id)
      added_ids << id
    end

    return if added_ids.empty?

    ActionLog.record(
      Current.person, "person-position-add", reason, { position_ids: added_ids }, person_id
    )
    added_ids.each { |id| PersonPositionLog.add_person(id, person_id) }
    PersonRole.clear_cache(person_id)
  end

  # Remove positions from a person. Log the action.
  def self.remove_ids_from_person(person_id, ids, reason)
    return if ids.empty?

    existing_ids = where(person_id: person_id, position_id: ids).pluck(:position_id)
    return if existing_ids.empty?

    where(person_id: person_id, position_id: existing_ids).delete_all
    ActionLog.record(
      Current.person, "person-position-remove", reason, { position_ids: existing_ids }, person_id
    )

    existing_ids.each do |id|
      PersonPositionLog.remove_person(id, person_id)
      Scheduling::Signup::Bulk.remove_future_sign_ups_for_position(person_id, id, "position revoked")
    end

    PersonRole.clear_cache(person_id)
  end

  # Log changes to person_position
  def self.log(person_id, id, action, reason = nil)
    ActionLog.record(
      Current.person, "person-position-#{action}", reason, { position_id: id }, person_id
    )
  end

  class << self
    private

    def build_position_scope(person_id, exclude_trainee_positions)
      scope = Position.select("position.*")
                      .joins(:person_position)
                      .where(active: true)
                      .where(person_position: { person_id: person_id })

      apply_trainee_exclusion(scope, exclude_trainee_positions)
    end

    def build_past_grants_scope(person_id, exclude_trainee_positions)
      scope = Position.select("position.*")
                      .joins(:person_position_log)
                      .where(person_position_log: { person_id: })
                      .where_year("person_position_log.left_on", Current.year)
                      .where(active: true)

      apply_trainee_exclusion(scope, exclude_trainee_positions)
    end

    def apply_trainee_exclusion(scope, exclude_trainee_positions)
      return scope unless exclude_trainee_positions

      scope.where.not(type: Position::TYPE_TRAINING).or(scope.where("title LIKE ?", "%Trainer%"))
    end

    def validate_position_grant_authorization!(position_id)
      tech_ninja = PositionRole.exists?(position_id: position_id, role_id: Role::TECH_NINJA)
      if tech_ninja && !Current.person&.has_role?(Role::TECH_NINJA)
        raise AuthorizationError, "Cannot grant position with Tech Ninja permission."
      end

      admin = PositionRole.exists?(position_id: position_id, role_id: Role::ADMIN)
      return unless admin && !Current.person&.has_role?(Role::ADMIN)

      raise AuthorizationError, "Cannot grant position with Admin permission."
    end
  end
end
