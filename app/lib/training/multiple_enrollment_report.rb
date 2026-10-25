# frozen_string_literal: true

# The multiple enrollments report (Laravel TrainingMultipleEnrollmentReport):
# the people signed up for more than one session of a training in a year, so a
# trainer can get the duplicate sign-up removed. Sessions that are two halves of
# one training ("Pre-Event Part 1" + "Part 2") count once, not twice.
#
# Deliberate deltas from upstream:
# - Upstream appends a section for every Position::ART_GRADUATE_TO_POSITIONS
#   entry. For Sandman that is the Sandman SHIFT position, where volunteering
#   several shifts is normal -- 34-49 people flagged every year, all noise. The
#   extra sections are gated on Training.has_mentees? instead, keeping the mentee
#   positions (the real signal) and dropping Sandman (decree 2026-08-02).
# - The multi-part rule is fixed rather than ported; see .group_key.
# - HQ Refresher is NOT folded into HQ Full Training (upstream scopes to the
#   exact position). Refresher slots ended in 2019 and no one since holds both,
#   so Training.session_position_ids would only shift historical numbers.
class Training::MultipleEnrollmentReport
  # A person and every session they signed up for in this section's position.
  Trainee = Data.define(:person, :slots)
  Section = Data.define(:position_id, :position_title, :trainees, :emails)
  Result = Data.define(:sections, :trainee_count, :enrollment_count, :max_enrollments)

  # "Part 1", "part  2" -- a single digit, upstream's rule.
  SESSION_PART = /\bPart\s*\d\b/i
  # Separators a stripped part token can strand mid-description.
  SEPARATORS = %r{[-–—/,\s]+}

  class << self
    # @param position [Position] the training position
    # @param year [Integer]
    # @return [Result]
    def execute(position, year)
      sections = section_position_ids(position).map { |id| build_section(id, position, year) }
      counts = sections.flat_map { |section| section.trainees.map { |trainee| trainee.slots.size } }

      Result.new(sections:,
                 trainee_count: counts.size,
                 enrollment_count: counts.sum,
                 max_enrollments: counts.max || 0)
    end

    private

    # The training itself, then its mentee positions -- but only for trainings
    # that actually have mentees (see the class comment).
    def section_position_ids(position)
      return [position.id] unless Training.has_mentees?(position)

      [position.id, *Position::ART_GRADUATE_TO_POSITIONS.dig(position.id, :positions)]
    end

    def build_section(position_id, position, year)
      slots_by_person = flagged_by_person(position_id, year)
      people = Person.where(id: slots_by_person.keys).order(:callsign)
      trainees = people.map { |person| Trainee.new(person:, slots: slots_by_person[person.id]) }

      Section.new(position_id:,
                  position_title: (position_id == position.id) ? position.title : Position.retrieve_title(position_id),
                  trainees:,
                  emails: trainees.filter_map { |trainee| trainee.person.email.presence })
    end

    # { person id => [Slot] } for everyone signed up to more than one session
    # group. Real Slot records rather than plucked columns so the page and the
    # CSV format times through the same timezone-aware accessors the rest of the
    # training suite uses.
    def flagged_by_person(position_id, year)
      # No active: filter -- upstream has none, and an inactive session someone
      # is still signed up to is exactly the problem this report exists to find.
      slots = Slot.where(position_id:, begins_year: year).index_by(&:id)
      return {} if slots.empty?

      pairs = PersonSlot.where(slot_id: slots.keys).pluck(:person_id, :slot_id)

      pairs.group_by(&:first).filter_map do |person_id, rows|
        next if rows.size < 2

        signed_up = rows.map { |(_, slot_id)| slots[slot_id] }.sort_by(&:begins)
        next if signed_up.map { |slot| group_key(slot) }.uniq.size < 2

        [person_id, signed_up]
      end.to_h
    end

    # A slot's session group. Descriptions carrying a "Part N" token collapse to
    # the description with that token -- and the separators it strands --
    # removed, so "Pre-Event Part 1" and "Pre-Event Part 2" share a key. Every
    # other slot is its own group of one, keyed by slot id (an Integer, which can
    # never collide with a String name key).
    #
    # Upstream instead pairs slots off two at a time, which gets two cases wrong:
    # someone in two COMPLETE groups (Pre-Event 1+2 and Post-Event 1+2) pairs off
    # entirely and is never flagged, and an odd-sized group (Parts 1, 2, 3)
    # leaves one slot unpaired and is always flagged.
    #
    # Slot.session_group_name is not reused: it only matches "Part N" at the END
    # of a description, so the 2019 "WAP/Part 1, Black Rock City, NV USA" slots
    # return nil from it and upstream groups them correctly only by accident
    # (nil == nil). Stripping the token in place handles them on purpose.
    #
    # description is NULL on real slots (17 on HQ Window Training, 6 on
    # Troubleshooter). PHP coerces null to ""; Ruby would raise, so .to_s is load
    # bearing, not defensive.
    def group_key(slot)
      text = slot.description.to_s
      return slot.id unless text.match?(SESSION_PART)

      text.gsub(SESSION_PART, " ").gsub(SEPARATORS, " ").strip.downcase
    end
  end
end
