# frozen_string_literal: true

class TrainerStatus < ApplicationRecord
  self.table_name = "trainer_status"

  STATUS_ATTENDED = "attended"
  STATUS_PENDING = "pending"
  STATUS_NO_SHOW = "no-show"

  belongs_to :slot
  belongs_to :trainer_slot, class_name: "Slot"
  belongs_to :person

  after_save :check_award_eligibility
  after_destroy :check_award_eligibility
  # Training.did_person_pass_for_year? counts teaching a session as passing it,
  # and RoleManager caches its answer.
  after_commit :purge_role_cache

  #
  # Find or initialize a trainer status record for a session (slot) and person.
  #
  # @param session_id [Integer]
  # @param person_id [Integer]
  # @return [TrainerStatus]
  #
  def self.first_or_new_for_session(session_id, person_id)
    find_or_initialize_by(slot_id: session_id, person_id: person_id)
  end

  #
  # Find trainer status records by slot and person IDs.
  #
  # @param slot_id [Integer]
  # @param person_ids [Array<Integer>]
  # @return [ActiveRecord::Relation]
  #
  def self.find_by_slot_person_ids(slot_id, person_ids)
    where(slot_id: slot_id, person_id: person_ids)
  end

  #
  # Did a person teach a session?
  #
  # @param person_id [Integer] the person to query
  # @param position_id [Integer] the position (Training / Green Dot Training / etc) to see if they taught
  # @param year [Integer] the year to check
  # @return [Boolean] return true if the person taught
  #
  def self.taught?(person_id, position_id, year)
    position_ids = Position::TRAINERS[position_id]
    return false unless position_ids

    Slot.active
        .joins(:trainer_status)
        .where(begins_year: year, position_id: position_ids)
        .where(trainer_status: { person_id: person_id, status: STATUS_ATTENDED })
        .exists?
  end

  #
  # Retrieve all the sessions the person may have taught.
  #
  # @param person_id [Integer] the person to check
  # @param position_ids [Array<Integer>] positions to check (Trainer / Trainer Assoc. / Uber /etc)
  # @param year [Integer] the year to check
  # @return [ActiveRecord::Relation]
  #
  def self.retrieve_sessions_for_person(person_id, position_ids, year)
    # Custom Left Join to get status only for this person, preserving slots where they have no status
    join_trainer_status = sanitize_sql_array([
                                               "LEFT JOIN trainer_status ON trainer_status.trainer_slot_id = slot.id AND trainer_status.person_id = ?",
                                               person_id
                                             ])

    Slot.select("slot.*, COALESCE(trainer_status.status, 'pending') as trainer_status")
        .active
        .joins(:person_slot)
        .where(person_slot: { person_id:  })
        .joins(join_trainer_status)
        .where(begins_year: year, position_id: position_ids)
        .order(:begins)
  end

  #
  # Delete all records referring to a slot. Used by slot deletion.
  #
  # @param slot_id [Integer]
  # @return [void]
  #
  def self.delete_for_slot(slot_id)
    where(slot_id: slot_id).delete_all
    where(trainer_slot_id: slot_id).delete_all
  end

  private

  def purge_role_cache
    RoleManager.purge_person(person_id)
  end

  def check_award_eligibility
    # Check if the trainer slot's position is eligible for awards
    if trainer_slot&.position&.awards_eligible?
      AwardManagement.rebuild_for_person_id(person_id)
    end
  end
end
