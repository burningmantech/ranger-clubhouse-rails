# frozen_string_literal: true

# A general note (ruled 2026-10-27; named cadre note until the owner renamed it
# and made it editable, 2026-10-28): what an ART's mentoring cadre notes about a
# mentee, tied to no mentor, shift, year or ART. Every roster the mentee is on
# shows all of them, newest first, and one is added with a roster's Save
# (ArtMentoring::Assignment). Its author alone edits or deletes it
# (Training::Mentoring::GeneralNotesController). Audited like the other note
# tables, which is where an edit's history lives: there is no updated_at.
class PersonMentoringNote < ApplicationRecord
  self.table_name = "person_mentoring_note"
  self.audit_model = true

  NOTES_MAX = 2_000
  # A note its author already wrote about the person within this long is a
  # resubmitted save -- its response lost, Save pressed again -- not a new one
  # (chosen 2026-10-27).
  RESUBMIT_WITHIN = 1.day

  belongs_to :person
  belongs_to :written_by, class_name: "Person"

  validates :notes, presence: true, length: { maximum: NOTES_MAX }

  # Every note about these people, newest first, with its author.
  def self.for_people(person_ids) = where(person_id: person_ids).includes(:written_by).order(created_at: :desc, id: :desc)

  def self.resubmitted?(person:, written_by:, notes:)
    where(person:, written_by:, created_at: RESUBMIT_WITHIN.ago..).pluck(:notes).include?(notes)
  end

  def written_by?(person) = written_by_id == person&.id
end
