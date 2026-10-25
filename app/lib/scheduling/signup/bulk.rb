# frozen_string_literal: true

module Scheduling
  module Signup
    # Per-person bulk removals of FUTURE signups, split out of the single-shift intake.
    # Driven by status changes (bonk / dismissal / past-prospective conversion) and
    # position revocation, where many of a person's upcoming shifts are dropped at once.
    #
    # Each method reuses Signup's locked delete + post-success orchestration via the shared
    # internal Signup#delete_signup, which writes the per-removal person-slot-remove
    # ActionLog itself. These loops used to write a SECOND one, because delete_signup's
    # own row recorded no slot_id -- so every bulk removal was audited twice, one row
    # naming the shift and one not. (The reports were not double-counting: they key on
    # slot_id, so the slot-less row was skipped and the removal counted once.)
    # delete_signup now records the slot_id and is the single audit path.
    #
    # It logs only on STATUS_SUCCESS, so these loops record the failures themselves --
    # a locked delete that rolls back leaves the person on the schedule, and the old
    # unconditional row at least left a trace. A row claiming a removal that did not
    # happen would be worse than none, so the failure gets its own event.
    # The present instant/year is read from Current.time, the Groundhog-Day-aware present,
    # instead of Time.zone.now ad-hoc; the ActionLog actor stays Current.person.
    module Bulk
      module_function

      # Remove all future signups for a person (current year).
      #
      # @param person_id [Integer]
      # @param reason [String]
      def remove_future_sign_ups(person_id, reason)
        now = Current.time
        rows = PersonSlot.select("person_slot.*")
                         .joins(:slot)
                         .where("slot.begins_year = ?", now.year)
                         .where("slot.begins > ?", now)
                         .where(person_id: person_id)
                         .includes(:slot)

        rows.each do |row|
          status = Scheduling::Signup.send(:delete_signup, person_id, row.slot, reason: reason)
          log_failed_removal(person_id, row.slot_id, reason, status)
        end
      end

      # Remove all future signups for a person and a given position (current year).
      #
      # @param person_id [Integer]
      # @param position_id [Integer]
      # @param reason [String]
      def remove_future_sign_ups_for_position(person_id, position_id, reason)
        now = Current.time
        rows = PersonSlot.select("person_slot.*")
                         .joins(:slot)
                         .where("slot.begins_year = ?", now.year)
                         .where("slot.begins >= ?", now)
                         .where("slot.position_id = ?", position_id)
                         .where(person_id: person_id)
                         .includes(:slot)

        rows.each do |row|
          status = Scheduling::Signup.send(:delete_signup, person_id, row.slot, reason:)
          log_failed_removal(person_id, row.slot_id, reason, status)
        end
      end

      # A bulk sweep does not stop for one stuck row, and neither caller reads the
      # status back, so without this a person bonked while a lock timed out stays on
      # the schedule with nothing anywhere to say why.
      def log_failed_removal(person_id, slot_id, reason, status)
        return if status == Scheduling::STATUS_SUCCESS

        ActionLog.record(Current.person, "person-slot-remove-failed", reason,
                         { slot_id:, status: }, person_id)
      end
    end
  end
end
