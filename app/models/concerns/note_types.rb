# frozen_string_literal: true

# Shared note type constants for timesheet notes
# Used by TimesheetNote and TimesheetMissingNote
module NoteTypes
  extend ActiveSupport::Concern

  TYPE_USER = "user"
  TYPE_HQ_WORKER = "hq-worker"
  TYPE_WRANGLER = "wrangler"
  TYPE_ADMIN = "admin"

  NOTE_TYPES = [TYPE_USER, TYPE_HQ_WORKER, TYPE_WRANGLER, TYPE_ADMIN].freeze

  included do
    validates :type, inclusion: { in: NOTE_TYPES }

    scope :non_admin, -> { where.not(type: TYPE_ADMIN) }
    scope :admin_only, -> { where(type: TYPE_ADMIN) }
  end

  def from_label(person_id)
    if person_id == create_person_id
      return "you"
    end

    callsign = create_person&.callsign || "person ##{create_person_id}"
    case type
    when TYPE_USER
      callsign
    when TYPE_HQ_WORKER
      "HQ Window volunteer #{callsign} on your behalf"
    when TYPE_WRANGLER
      "Timesheet Review #{callsign}"
    else
      "unknown type #{type}"
    end
  end
end
