# frozen_string_literal: true

class ScheduleLog
  class << self
    # Schedule log entry
    class ScheduleLogEntry
      attr_accessor :slot_id,
                    :slot_description,
                    :slot_begins,
                    :position_id,
                    :position_title,
                    :added,
                    :removed,
                    :no_signup

      def initialize(slot_id:, slot_description:, slot_begins:, position_id:, position_title:,
                     added: [], removed: [], no_signup: false)
        @slot_id = slot_id
        @slot_description = slot_description
        @slot_begins = slot_begins
        @position_id = position_id
        @position_title = position_title
        @added = added
        @removed = removed
        @no_signup = no_signup
      end
    end

    # Report on slots the given person signed up and/or was removed from
    #
    # @param person_id [Integer]
    # @param year [Integer]
    # @return [Array<ScheduleLogEntry>]
    def retrieve(person_id, year)
      rows = ActionLog.where(target_person_id: person_id)
                      .where_year("created_at", year)
                      .where(event: %w[person-slot-add person-slot-remove])
                      .includes(:person)

      slots = {}

      rows.each do |row|
        person_info = {
          id: row.person_id,
          callsign: row.person&.callsign || "Deleted ##{row.person_id}"
        }
        # Coerced, not read raw: the id is a String in some years and an Integer
        # in others, and this is a grouping key -- ungrouped, one shift splits
        # into two entries, the sign-up under one and the removal under the other.
        slot_id = ActionLog.slot_id_from_data(row.data)

        slots[slot_id] ||= build_schedule_log_entry(slot_id, row, person_id)
        log_info = slots[slot_id]

        if row.event == "person-slot-add"
          log_info.added << { date: row.created_at, person: person_info }
        else
          log_info.removed << { date: row.created_at, person: person_info }
        end
      end

      slots.values.sort_by(&:slot_begins)
    end

    private

    # Build schedule log entry for a slot
    def build_schedule_log_entry(slot_id, row, person_id)
      slot = Slot.find_by(id: slot_id)
      log_info = if slot
                   ScheduleLogEntry.new(
                     slot_id: slot_id,
                     slot_description: slot.description,
                     slot_begins: slot.begins,
                     position_id: slot.position_id,
                     position_title: slot.position&.title || "Deleted ##{slot.position_id}"
                   )
                 else
                   ScheduleLogEntry.new(
                     slot_id: slot_id,
                     slot_description: "Deleted ##{slot_id}",
                     slot_begins: row.created_at,
                     position_id: 0,
                     position_title: "unknown"
                   )
                 end

      log_info.no_signup = true unless PersonSlot.exists?(person_id: person_id, slot_id: slot_id)

      log_info
    end
  end
end
