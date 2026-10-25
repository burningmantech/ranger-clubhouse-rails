# frozen_string_literal: true

# A per-training-session note about a trainee, analogous to PersonIntakeNote for
# the intake teams. Ported from port/TraineeNote.php. Referenced by
# Training.retrieve_training_history_for_ids; create/update/delete are audited to
# ActionLog (the PHP model's $auditModel = true).
class TraineeNote < ApplicationRecord
  self.table_name = "trainee_note"
  self.audit_model = true

  belongs_to :person
  belongs_to :person_source, class_name: "Person", optional: true
  belongs_to :slot

  # All training notes for a person in a slot, oldest first, with the note's
  # author eager-loaded.
  def self.find_all_for_person_slot(person_id, slot_id)
    where(person_id: person_id, slot_id: slot_id)
      .order(:created_at)
      .includes(:person_source)
  end

  # Remove every note for a slot. Used when a slot is deleted. A bulk delete
  # (no per-row callbacks/audit), matching the PHP mass ->delete().
  def self.delete_for_slot(slot_id)
    where(slot_id: slot_id).delete_all
  end

  def self.record(person_id:, slot_id:, note:, is_log: false, person_source_id: Current.person_id)
    create!(
      person_id: person_id,
      slot_id: slot_id,
      note: note,
      is_log: is_log,
      person_source_id: person_source_id
    )
  end
end
