# frozen_string_literal: true

class PersonIntakeNote < ApplicationRecord
  self.table_name = "person_intake_note"
  # The `type` column is a note-type enum, not an STI discriminator.
  self.inheritance_column = nil
  # Create/update/delete are audited to ActionLog (PHP model's $auditModel = true).
  self.audit_model = true

  TYPES = %w[mentor rrn personnel vc].freeze

  belongs_to :person
  belongs_to :person_source, class_name: "Person"

  validates :type, inclusion: { in: TYPES }

  def self.record(person_id:, year:, type:, note:, is_log: false, person_source_id: Current.person_id)
    create!(
      person_id: person_id,
      year: year,
      type: type,
      note: note,
      is_log: is_log,
      person_source_id: person_source_id
    )
  end
end
