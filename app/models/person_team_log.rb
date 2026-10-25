# frozen_string_literal: true

# PersonTeamLog tracks the history of team membership grants and revocations for people.
# Each record represents when a person joined a team and optionally when they left it.
class PersonTeamLog < ApplicationRecord
  self.table_name = "person_team_log"

  belongs_to :person
  belongs_to :team

  validates :person_id, :team_id, :joined_on, presence: true
  validate :left_on_must_be_after_joined_on

  def self.add_person(team_id, person_id)
    create!(
      person_id: person_id,
      team_id: team_id,
      joined_on: Current.time
    )
  end

  def self.remove_person(team_id, person_id)
    where(person_id: person_id, team_id: team_id, left_on: nil).find_each do |record|
      record.update!(left_on: Current.time)
    end
  end

  def left_on=(value)
    super(value.presence)
  end

  private

  def left_on_must_be_after_joined_on
    return if left_on.blank? || joined_on.blank?
    return unless left_on < joined_on

    errors.add(:left_on, "The left on date must be on or after the joined on date.")
  end
end
