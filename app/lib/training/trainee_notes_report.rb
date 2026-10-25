# frozen_string_literal: true

# The all-trainee-notes report (Laravel TrainingNotesReport): everyone marked
# as passed for an ART's sessions in a year, with the notes trainers left on
# each session, so an ART lead can review feedback when picking mentees or
# evaluating trainees.
#
# Standing classifies each person against the ART's graduate configuration:
# veteran (holds the graduated position), mentee (holds one of the mentee
# positions), or prospective (neither). An ART with no configuration -- or one
# missing the veteran/mentee keys -- classifies everyone prospective, as
# upstream does.
#
# Deliberate deltas from upstream:
# - Upstream groups notes by person_id ALONE and then replays that whole group
#   inside its per-trainee_status-row loop, stamping each note's session
#   metadata from the row rather than from the note. Two bugs follow, both live
#   in real data: someone who passed two sessions gets every note duplicated
#   once per extra row, and a note left on a session the person did NOT pass
#   renders under the header and rank of a session they did. Notes here are
#   keyed by (person_id, slot_id) instead, so each note lands on its own
#   session; a note on a not-passed session becomes its own entry with
#   passed: false, which the page labels rather than disguises (decree
#   2026-08-03).
#
# Kept from upstream on purpose:
# - Notes are bounded by the passed rows' people AND slots. A note only appears
#   when its session had at least one person pass it, which is what makes the
#   report "this year's sessions" rather than "every note ever filed".
# - Sessions are scoped to the training position exactly, not
#   Training.session_position_ids: HQ Full Training's refresher slots are not
#   folded in, matching upstream's scoping.
class Training::TraineeNotesReport
  STANDING_VETERAN = "veteran"
  STANDING_MENTEE = "mentee"
  STANDING_PROSPECTIVE = "prospective"
  STANDINGS = [STANDING_VETERAN, STANDING_MENTEE, STANDING_PROSPECTIVE].freeze

  # One session a person attended. notes are the ones filed on that exact
  # (person, session) pair -- the whole point of the port (see above).
  SessionEntry = Data.define(:slot, :rank, :passed, :notes) do
    def notes? = notes.any?
  end

  Trainee = Data.define(:person, :standing, :sessions) do
    def callsign = person.callsign
    def status = person.status
    def note_count = sessions.sum { |session| session.notes.size }
    def notes? = sessions.any?(&:notes?)
  end

  class << self
    # @param position [Position] the training position
    # @param year [Integer]
    # @return [Array<Trainee>] by callsign, case-insensitively
    def execute(position, year)
      rows = passed_rows(position, year)
      return [] if rows.empty?

      people = rows.map(&:person).index_by(&:id)
      slots = rows.to_h { |row| [row.slot_id, row.slot] }
      sessions = session_entries(rows, notes_by_pair(people.keys, slots.keys), slots)
      standing = standing_by_person(position, people.keys)

      people.values
            .map { |person| Trainee.new(person:, standing: standing[person.id], sessions: sessions[person.id]) }
            .sort_by { |trainee| trainee.callsign.downcase }
    end

    private

    # Everyone who passed one of the year's sessions and is still signed up to
    # it -- upstream requires the person_slot row as well as the passing grade,
    # so a trainee_status left behind by a roster removal does not resurrect
    # someone.
    def passed_rows(position, year)
      TraineeStatus.joins(slot: :person_slot)
                   .where("person_slot.person_id = trainee_status.person_id")
                   .where(slot: { begins_year: year, active: true, position_id: position.id })
                   .passed
                   .includes(:person, :slot)
                   .to_a
    end

    # { [person id, slot id] => [TraineeNote] }, oldest note first. is_log rows
    # are the audit trail (rank changes and the like), never trainer feedback.
    def notes_by_pair(person_ids, slot_ids)
      TraineeNote.where(person_id: person_ids, slot_id: slot_ids, is_log: false)
                 .order(:created_at)
                 .group_by { |note| [note.person_id, note.slot_id] }
    end

    # { person id => [SessionEntry] } in session order: one entry per passed
    # session, plus one per session that only carries notes (see the class
    # comment). Every noted person has a passed row -- notes are bounded by the
    # passed rows' people -- so no entry is ever orphaned. slots is only needed
    # for that second group; a passed row carries its own preloaded slot.
    def session_entries(rows, notes, slots)
      entries = Hash.new { |hash, person_id| hash[person_id] = [] }

      rows.each do |row|
        entries[row.person_id] << SessionEntry.new(slot: row.slot, rank: row.rank, passed: true,
                                                   notes: notes[[row.person_id, row.slot_id]] || [])
      end

      not_passed = notes.keys - rows.map { |row| [row.person_id, row.slot_id] }
      ranks = ranks_for(not_passed)
      not_passed.each do |pair|
        person_id, slot_id = pair
        entries[person_id] << SessionEntry.new(slot: slots[slot_id], rank: ranks[pair], passed: false,
                                               notes: notes[pair])
      end

      entries.each_value { |list| list.sort_by! { |entry| entry.slot.begins } }
      entries
    end

    # Ranks for the not-passed pairs. Records, not a pluck: the rank column has
    # a legacy default of 0 meaning "no rank", and only the model's getter
    # normalizes it.
    def ranks_for(pairs)
      return {} if pairs.empty?

      # The cross product is a superset of the wanted pairs, so slice it back
      # down; in the worst year on record it over-fetches 32 rows for 19.
      TraineeStatus.where(person_id: pairs.map(&:first).uniq, slot_id: pairs.map(&:last).uniq)
                   .index_by { |status| [status.person_id, status.slot_id] }
                   .slice(*pairs)
                   .transform_values(&:rank)
    end

    # { person id => standing }. One query for both position sets, partitioned
    # in Ruby (TrainingSession::Graduation fetches its two sets the same way).
    #
    # The has_mentees? gate is load bearing, not a shortcut around a blank
    # check: Sandman lists mentee positions WITHOUT the flag, and reading them
    # would file Sandmen as mentees.
    def standing_by_person(position, person_ids)
      graduate = Position::ART_GRADUATE_TO_POSITIONS[position.id] || {}
      veteran_id = graduate[:veteran]
      mentee_ids = Training.has_mentees?(position) ? Array(graduate[:positions]) : []

      held = position_holders(person_ids, [veteran_id, *mentee_ids].compact)

      person_ids.index_with do |person_id|
        held_by_person = held[person_id] || []
        if held_by_person.include?(veteran_id)
          STANDING_VETERAN
        elsif held_by_person.intersect?(mentee_ids)
          STANDING_MENTEE
        else
          STANDING_PROSPECTIVE
        end
      end
    end

    # { person id => [position id] }, limited to the positions standing is
    # computed from.
    def position_holders(person_ids, position_ids)
      return {} if position_ids.empty?

      PersonPosition.where(person_id: person_ids, position_id: position_ids)
                    .pluck(:person_id, :position_id)
                    .group_by(&:first)
                    .transform_values { |pairs| pairs.map(&:last) }
    end
  end
end
