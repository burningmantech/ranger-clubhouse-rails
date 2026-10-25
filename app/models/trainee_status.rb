# frozen_string_literal: true

# A trainer's verdict on one trainee for one training session -- pending until
# scored, then passed, no-show or not-passed -- with an optional rank and, for
# In-Person Training, whether feedback was delivered.
#
# A pending row reads exactly like no row: one exists before a verdict only
# because a rank or a note was saved ahead of it.
class TraineeStatus < ApplicationRecord
  self.table_name = "trainee_status"

  STATUS_PENDING = "pending" # not scored yet -- the default
  STATUS_PASSED = "passed"
  STATUS_NO_SHOW = "no-show"
  STATUS_NOT_PASSED = "not-passed" # attended, and did not pass
  STATUSES = [STATUS_PENDING, STATUS_PASSED, STATUS_NO_SHOW, STATUS_NOT_PASSED].freeze

  belongs_to :person
  belongs_to :slot

  validates :status, inclusion: { in: STATUSES }

  # Training.did_person_pass_for_year? reads this row and RoleManager caches its
  # answer, so a saved or removed verdict purges the person's role set.
  after_commit :purge_role_cache

  scope :passed, -> { where(status: STATUS_PASSED) }

  def passed? = status == STATUS_PASSED

  # Normalize empty rank to nil
  def rank=(value)
    super(value.presence)
  end

  # The legacy column default is 0 alongside NULLs -- both mean "no rank
  # given" (same normalization as PersonIntake's rank columns). 0 is truthy
  # in Ruby, so raw reads would render "Rank 0" and log bogus rank-change
  # audit notes.
  def rank
    value = super
    value.nil? || value.zero? ? nil : value
  end

  # Find trainee_status records with joined slot for a person & year, in
  # session order -- the caller picks out a pass itself.
  # Returns merged trainee_status & slot data.
  # @param person_id [Integer] person to find
  # @param year [Integer] year to look up
  # @param position_id [Integer, nil] optional position filter
  # @return [ActiveRecord::Relation<TraineeStatus>]
  def self.find_for_person_year(person_id, year, position_id = nil)
    scope = joins(slot: :person_slot)
              .where(slot: { begins_year: year, active: true })
              .where(person_slot: { person_id: })
              .where(person_id:)
              .order(Slot.arel_table[:begins])

    if position_id.present?
      scope = scope.where(slot: { position_id: Training.session_position_ids(position_id) })
    end

    scope
  end

  # Did the person pass training in a given year?
  # @param person_id [Integer]
  # @param position_id [Integer]
  # @param year [Integer]
  # @return [Boolean]
  def self.did_person_pass_for_year?(person_id, position_id, year)
    passed.joins(:slot)
      .where(person_id:)
      .where(slot: { position_id: Training.session_position_ids(position_id), begins_year: year })
      .exists?
  end

  # Find or initialize a trainee status for a session
  # @param person_id [Integer]
  # @param session_id [Integer] slot_id
  # @return [TraineeStatus]
  def self.first_or_new_for_session(person_id, session_id)
    find_or_initialize_by(person_id: person_id, slot_id: session_id)
  end

  # Did the person pass a specific training session?
  # @param person_id [Integer]
  # @param slot_id [Integer]
  # @return [Boolean]
  def self.did_person_pass_session?(person_id, slot_id)
    passed.exists?(person_id:, slot_id:)
  end

  # Delete all records referring to a slot. Used by slot deletion.
  # @param slot_id [Integer]
  def self.delete_for_slot(slot_id)
    where(slot_id: slot_id).delete_all
  end

  private

  def purge_role_cache
    RoleManager.purge_person(person_id)
  end
end
