# frozen_string_literal: true

# A mentee shift the mentee did not complete because no mentor was available
# (owner, 2026-11-13): the roster's "No mentors available" box
# (ArtMentoring::Assignment). A row names the mentee, the timesheet entry the
# box was ticked on, and the shift's slot (none for a sign-in that matched no
# shift). It is found by its entry, which a unique key holds to one row, so it
# follows an entry corrected onto another shift. Unticking the box deletes the
# row, so `incomplete` is true on every row the roster writes. Audited, which
# is where who and when are kept: there are no timestamps.
class PersonMentoringShift < ApplicationRecord
  self.table_name = "person_mentoring_shift"
  self.audit_model = true

  belongs_to :person
  belongs_to :slot, optional: true
  belongs_to :timesheet, optional: true

  validate :has_a_key

  scope :incomplete, -> { where(incomplete: true) }

  # The rows ticked on these timesheet entries.
  def self.for_entries(timesheet_ids) = incomplete.where(timesheet_id: timesheet_ids)

  private

  def has_a_key
    errors.add(:base, "A mentoring shift row needs a shift or a timesheet entry.") unless slot_id || timesheet_id
  end
end
