# frozen_string_literal: true

# Form object for the person membership editor.
class PersonMembershipForm
  include ActiveModel::Model

  attr_reader :team_ids, :manager_ids, :position_ids

  def initialize(attributes = {})
    super()
    assign_attributes(attributes || {})
  end

  def assign_attributes(attributes)
    values = attributes.respond_to?(:to_h) ? attributes.to_h.symbolize_keys : {}

    self.team_ids = values[:team_ids]
    self.manager_ids = values[:manager_ids]
    self.position_ids = values[:position_ids]
  end

  def team_ids=(value)
    @team_ids = normalize_ids(value)
  end

  def manager_ids=(value)
    @manager_ids = normalize_ids(value)
  end

  def position_ids=(value)
    @position_ids = normalize_ids(value)
  end

  def persisted?
    false
  end

  def save(actor:, person:, is_admin:)
    ApplicationRecord.transaction do
      Membership.update_positions_for_person(
        user_id: actor.id,
        person: person,
        position_ids: position_ids,
        reason: update_reason,
        is_admin: is_admin
      )

      Membership.update_teams_for_person(
        user_id: actor.id,
        person_id: person.id,
        team_ids: team_ids,
        reason: update_reason,
        is_admin: is_admin
      )

      Membership.update_management_for_person(
        user_id: actor.id,
        person_id: person.id,
        team_ids: manager_ids,
        reason: update_reason,
        is_admin: is_admin
      )
    end

    true
  rescue AuthorizationError, ActiveRecord::ActiveRecordError => e
    errors.add(:base, e.message.presence || "Unable to update memberships and positions.")
    false
  end

  private

  # A list the request did not send stays nil, which Membership leaves alone.
  # A sent list, even an empty one, replaces what the user can manage.
  def normalize_ids(values)
    IdList.parse(values) unless values.nil?
  end

  def update_reason
    "Person membership update"
  end
end
