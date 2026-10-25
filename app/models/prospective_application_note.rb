# frozen_string_literal: true

class ProspectiveApplicationNote < ApplicationRecord
  self.table_name = "prospective_application_note"
  # The `type` column is a note type, not an STI discriminator.
  self.inheritance_column = nil

  TYPE_RRN = "rrn"
  TYPE_VC = "vc"
  TYPE_VC_FLAG = "vc-flag"
  TYPE_VC_COMMENT = "vc-comment"

  ALL_TYPES = [TYPE_RRN, TYPE_VC, TYPE_VC_FLAG, TYPE_VC_COMMENT].freeze

  belongs_to :person, optional: true
  belongs_to :prospective_application

  validates :note, presence: { message: "Please enter some text." }
  validates :type, inclusion: { in: ALL_TYPES }

  def self.find_note_for_application!(application_id, note_id)
    where(prospective_application_id: application_id).find(note_id)
  end
end
