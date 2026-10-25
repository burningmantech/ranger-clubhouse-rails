# frozen_string_literal: true

# Form object for the combined "append a note and/or change a rank" action on
# a single intake team+year. Ported from IntakeController::appendNote
# (port/api/IntakeController.php) plus the client-side guard in
# port/components/intake-note-edit.js's submitNoteAction -- the PHP endpoint
# itself trusts the client and enforces nothing about note/ranking being
# present; we enforce it here since our port should be stricter, not looser.
class IntakeNoteForm
  include ActiveModel::Model

  attr_accessor :type, :year, :note, :ranking, :person, :current_rank

  validates :type, inclusion: { in: PersonIntakeNote::TYPES }
  validates :year, presence: true, numericality: { only_integer: true }
  validate :ranking_in_range
  validate :require_note_or_rank_change

  def persisted? = false

  def save(actor:)
    return false unless valid?

    ApplicationRecord.transaction do
      if trimmed_note.present?
        PersonIntakeNote.record(person_id: person.id, year: year.to_i, type: type, note: trimmed_note,
                                is_log: false, person_source_id: actor.id)
      end

      # Mirrors the PHP `isset($params['ranking'])` check: a blank/no-rank
      # selection never triggers a rank change, even if current_rank is set
      # (upstream cannot clear a rank back to "no rank" via this endpoint).
      if rank_will_change?
        intake = PersonIntake.find_for_person_year_or_new(person.id, year.to_i)
        intake.public_send("#{type}_rank=", normalized_ranking)
        intake.save!

        PersonIntakeNote.record(person_id: person.id, year: year.to_i, type: type,
                                is_log: true, person_source_id: actor.id,
                                note: "rank change [#{current_rank || 'no rank'}] -> [#{normalized_ranking || 'no rank'}]")
      end
    end

    true
  rescue ActiveRecord::ActiveRecordError => e
    errors.add(:base, e.message.presence || "Unable to save intake note.")
    false
  end

  private

  def trimmed_note
    note.to_s.strip
  end

  def normalized_ranking
    ranking.presence&.to_i
  end

  def rank_will_change?
    !normalized_ranking.nil? && normalized_ranking != current_rank
  end

  # The select only ever offers "" or 1-4, but a hand-crafted POST could carry
  # any integer; ranks outside 1-4 are meaningless and must not be persisted.
  def ranking_in_range
    r = normalized_ranking
    return if r.nil? || (Intake::ABOVE_AVERAGE..Intake::FLAG).cover?(r)

    errors.add(:ranking, "The ranking must be between #{Intake::ABOVE_AVERAGE} and #{Intake::FLAG}.")
  end

  # Port of the Ember modal's "Please select a rank and/or enter a note"
  # guard (submitNoteAction) -- if neither the note nor the rank is actually
  # changing, there is nothing to save. Uses the same rank_will_change?
  # predicate `save` acts on, so this can never pass validation only to
  # silently no-op (e.g. clearing to "no rank" against an existing rank).
  def require_note_or_rank_change
    return if trimmed_note.present?
    return if rank_will_change?

    errors.add(:base, "Please select a rank and/or enter a note")
  end
end
