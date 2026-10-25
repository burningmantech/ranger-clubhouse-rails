# frozen_string_literal: true

module Scheduling
  # The seam for the locked, transactional persistence of a signup: insert (with the
  # under-lock capacity re-check) and delete (with audit reason + recount). Isolating it
  # lets the write path be exercised by an InMemorySlotStore in tests, and keeps the
  # locking/error-mapping in one place.
  #
  # ActiveRecordSlotStore is the production adapter; its bodies are moved verbatim from
  # the former Management#create_signup / #delete_signup so behaviour is byte-identical.
  class ActiveRecordSlotStore
    # Locked transactional insert. Re-validates capacity UNDER the row lock (the unlocked
    # preview may be stale) by re-reading the trainer count fresh. Returns a Scheduling status.
    def insert_signup(person_id, slot_id, force:)
      status = STATUS_SUCCESS
      Slot.transaction do
        update_slot = Slot.lock.find(slot_id)

        unless force
          # Freshness contract for the write path: re-read the trainer count UNDER
          # the lock (the unlocked preview may be stale). The guard + multiply live
          # in SlotCapacity; here we only obtain the fresh value.
          trainer_signed_up = Slot.where(id: update_slot.trainer_slot_id).pick(:signed_up).to_i if update_slot.trainer_slot_id
          effective_max = Scheduling::SlotCapacity.new(update_slot).effective_max(trainer_signed_up: trainer_signed_up)

          if update_slot.signed_up >= effective_max
            status = STATUS_FULL
            raise ActiveRecord::Rollback
          end
        end

        PersonSlot.create!(person_id: person_id, slot_id: update_slot.id)
        update_slot.signed_up += 1
        update_slot.save!
        VehicleEligibility.purge_cache(person_id, update_slot.begins_year)
      rescue ActiveRecord::RecordNotUnique
        status = STATUS_EXISTS
        raise ActiveRecord::Rollback
      rescue ActiveRecord::StatementInvalid, ActiveRecord::LockWaitTimeout
        status = STATUS_DB_FAILURE
        raise ActiveRecord::Rollback
      end

      status
    end

    # Locked transactional delete. Sets the audit reason before destroy and recounts
    # signed_up. Returns a Scheduling status. Post-success orchestration (parent/child
    # recompute, empty-slot alerts, audit log) stays with the caller.
    def delete_signup(person_id, slot, reason: nil)
      status = STATUS_SUCCESS
      Slot.transaction do
        person_slot = PersonSlot.lock.find_by(person_id: person_id, slot_id: slot.id)

        if person_slot
          begin
            person_slot.audit_reason = reason if reason
            person_slot.destroy!
            slot.update!(signed_up: PersonSlot.where(slot_id: slot.id).count)
            VehicleEligibility.purge_cache(person_id, slot.begins_year)
          rescue ActiveRecord::StatementInvalid, ActiveRecord::LockWaitTimeout
            status = STATUS_DB_FAILURE
            raise ActiveRecord::Rollback
          end
        else
          status = STATUS_MISSING_SIGNUP
        end
      end

      status
    end
  end
end
