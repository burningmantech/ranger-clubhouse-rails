# frozen_string_literal: true

# PersonPositionLog tracks the history of position grants and revocations for people.
# Each record represents when a person was granted a position and optionally when it was revoked.
class PersonPositionLog < ApplicationRecord
  self.table_name = "person_position_log"

  # Relationships
  belongs_to :person
  belongs_to :position

  # Validations
  validates :person_id, :position_id, :joined_on, presence: true
  validate :left_on_must_be_after_joined_on

  # Find position log records based on the given criteria
  # @param query [Hash] optional keys: :person_id, :position_id
  # @return [ActiveRecord::Relation]
  def self.find_for_query(query = {})
    person_id = query[:person_id]
    position_id = query[:position_id]

    scope = all
    scope = person_id.present? ?  scope.where(person_id: person_id) : scope.includes(:person)

    if position_id.present?
      scope.where(position_id: position_id).order(:joined_on)
    else
      scope.includes(:position).references(:position).order("positions.title", :joined_on)
    end
  end

  # Log a position grant
  # @param position_id [Integer]
  # @param person_id [Integer]
  def self.add_person(position_id, person_id)
    create!(
      person_id: person_id,
      position_id: position_id,
      joined_on: Current.time
    )
  end

  # Log a position revoke by setting left_on to today
  # @param position_id [Integer]
  # @param person_id [Integer]
  def self.remove_person(position_id, person_id)
    where(person_id: person_id, position_id: position_id, left_on: nil).update_all(left_on: Current.time)
  end

  # Load associated person and position
  def load_relationships
    person
    position
    self
  end

  def left_on=(value)
    super(value.presence)
  end

  private

  def left_on_must_be_after_joined_on
    return if left_on.blank? || joined_on.blank?

    if left_on < joined_on
      errors.add(:left_on, "The left on date must be on or after the joined on date.")
    end
  end
end
