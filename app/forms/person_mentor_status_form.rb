# frozen_string_literal: true

# Form object that updates the shared status across every Alpha person_mentor
# row for a given (person_id, mentor_year). Used by the admin mentoring interface.
class PersonMentorStatusForm
  include ActiveModel::Model

  attr_accessor :mentor_year, :status, :person

  validates :mentor_year, presence: true, numericality: { only_integer: true }
  validates :status, presence: true, inclusion: { in: PersonMentor::STATUSES }
  validate :records_must_exist

  def persisted? = false

  def save(actor:)
    return false unless valid?

    _ = actor
    ApplicationRecord.transaction do
      scope.update_all(status: status)
    end
    true
  rescue ActiveRecord::ActiveRecordError => e
    errors.add(:base, e.message.presence || "Unable to update mentor status.")
    false
  end

  private

  def scope
    PersonMentor.where(person_id: person.id, mentor_year: mentor_year.to_i, position_id: Position::ALPHA)
  end

  def records_must_exist
    return if scope.exists?

    errors.add(:mentor_year, "This person has no mentor records for that mentor year.")
  end
end
