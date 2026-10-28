# frozen_string_literal: true

# PersonSlot model
# Represents a person's signup for a specific slot/shift.
class PersonSlot < ApplicationRecord
  self.table_name = "person_slot"
  self.audit_model = true

  # MVR Signup info class for retrieving eligible signups
  class MvrSignup
    attr_accessor :id,
                  :begins,
                  :position_id,
                  :position_title,
                  :timezone

    def initialize(id:, begins:, position_id:, position_title:, timezone:)
      @id = id
      @begins = begins
      @position_id = position_id
      @position_title = position_title
      @timezone = timezone
    end
  end

  # Associations
  belongs_to :person
  belongs_to :slot

  # Callbacks
  after_create :update_signup_years
  after_destroy :update_signup_years

  class << self
    # Is a person signed up for a given slot?
    #
    # @param person_id [Integer]
    # @param slot_id [Integer]
    # @return [Boolean]
    def have_slot?(person_id, slot_id)
      exists?(person_id: person_id, slot_id: slot_id)
    end

    # Delete all slot sign-ups. Used by slot deletion.
    #
    # @param slot_id [Integer]
    def delete_for_slot(slot_id)
      rows = where(slot_id: slot_id)
      user = Current.person

      rows.each do |row|
        ActionLog.record(user, "person-slot-remove", "slot deletion",
                         { slot_id: slot_id }, row.person_id)
      end

      where(slot_id: slot_id).delete_all
    end

    # Is the person signed up for a Motor Vehicle Request eligible shift?
    #
    # @param person_id [Integer]
    # @param year [Integer]
    # @return [Boolean]
    def mvr_eligible_signups?(person_id, year)
      common_vehicle_eligibility?(person_id, year, :mvr_eligible) ||
        common_vehicle_eligibility?(person_id, year, :mvr_signup_eligible)
    end

    # Retrieve all MVR signup-eligible shifts for a person
    #
    # @param person_id [Integer]
    # @param year [Integer]
    # @return [Array<MvrSignup>]
    def retrieve_mvr_signups(person_id, year)
      rows = select("slot.id, slot.begins, slot.timezone, slot.position_id, position.title as position_title")
             .joins(slot: :position)
             .where(person_id: person_id)
             .where(slot: { begins_year: year, active: true })
             .where(position: { mvr_signup_eligible: true })
             .order("slot.begins")

      rows.map do |row|
        MvrSignup.new(
          id: row.id,
          begins: row.begins,
          position_id: row.position_id,
          position_title: row.position_title,
          timezone: row.timezone
        )
      end
    end

    # Is the person signed up for a Personal Vehicle Request eligible shift?
    #
    # @param person_id [Integer]
    # @param year [Integer]
    # @return [Boolean]
    def pvr_eligible_signups?(person_id, year)
      common_vehicle_eligibility?(person_id, year, :pvr_eligible)
    end

    # Does the person have a vehicle (MVR or PVR) qualification?
    #
    # @param person_id [Integer]
    # @param year [Integer]
    # @param column [Symbol] The position column to check
    # @return [Boolean]
    def common_vehicle_eligibility?(person_id, year, column)
      Position.joins(slot: :person_slot)
              .where(active: true)
              .where(column => true)
              .where(slot: { active: true, begins_year: year })
              .where(person_slot: { person_id: person_id })
              .exists?
    end
  end

  private

  # Update the person's signup years after create/destroy
  def update_signup_years
    YearsManagement.update_signup_years(person_id)
  end
end
