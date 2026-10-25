# frozen_string_literal: true

class TimesheetMissingNote < ApplicationRecord
  include NoteTypes

  self.table_name = "timesheet_missing_note"
  self.inheritance_column = "none"

  # Associations
  belongs_to :timesheet_missing
  belongs_to :create_person, class_name: "Person", optional: true

  # Validations
  validates :note, presence: true

  # Scopes
  scope :for_timesheet_missing, ->(timesheet_missing_id) { where(timesheet_missing_id: timesheet_missing_id) }
  scope :ordered, -> { order(:created_at) }

  class << self
    # Record a timesheet missing note
    #
    # @param timesheet_missing_id [Integer] The ID of the timesheet missing entry
    # @param person_id [Integer, nil] The person creating the note (nil for bot notes)
    # @param note [String, nil] The note text
    # @param note_type [String] The type of note
    def record(timesheet_missing_id, person_id, note, note_type)
      note = note&.strip
      return if note.blank?

      create!(
        timesheet_missing_id: timesheet_missing_id,
        create_person_id: person_id,
        note: note,
        type: note_type,
        created_at: Current.time
      )
    end
  end
end
