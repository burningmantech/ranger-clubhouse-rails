# frozen_string_literal: true

class TimesheetNote < ApplicationRecord
  include NoteTypes

  self.table_name = "timesheet_note"
  self.inheritance_column = "none"

  TYPE_USER = "user"
  TYPE_HQ_WORKER = "hq-worker"
  TYPE_WRANGLER = "wrangler"
  TYPE_ADMIN = "admin"

  # Associations
  belongs_to :timesheet
  belongs_to :create_person, class_name: "Person", optional: true

  # Validations
  validates :note, presence: true

  # Scopes
  scope :for_timesheet, ->(timesheet_id) { where(timesheet_id: timesheet_id) }
  scope :ordered, -> { order(:created_at) }

  class << self
    # Record a timesheet note
    #
    # @param timesheet_id [Integer] The ID of the timesheet entry
    # @param person_id [Integer, nil] The person creating the note (nil for bot notes)
    # @param note [String, nil] The note text
    # @param note_type [String] The type of note
    def record(timesheet_id, person_id, note, note_type)
      note = note&.strip
      return if note.blank?

      create!(
        timesheet_id: timesheet_id,
        create_person_id: person_id,
        note: note,
        type: note_type,
        created_at: Current.time
      )
    end
  end
end
