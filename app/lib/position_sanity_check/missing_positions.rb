# frozen_string_literal: true

# Accounts missing the positions everybody is supposed to have: the All
# Rangers set for Rangers, the New User set for every live account.
#
# Two sets with two different audiences, merged per person -- an active Ranger
# can be missing one of each and is one finding either way.
class PositionSanityCheck::MissingPositions < PositionSanityCheck::Base
  # Who gets the All Rangers positions. Upstream's list, which is narrower
  # than Person::ACTIVE_STATUSES -- a retired Ranger is not given them back.
  RANGER_STATUSES = [Person::ACTIVE, Person::INACTIVE, Person::INACTIVE_EXTENSION].freeze

  # Who gets the New User positions: anyone with a live account.
  USER_STATUSES = [Person::ACTIVE, Person::ALPHA, Person::AUDITOR, Person::INACTIVE,
                   Person::INACTIVE_EXTENSION, Person::PROSPECTIVE, Person::ECHELON].freeze

  class << self
    # The board wants a number, not the rows. Stopping at the id-keyed hash
    # skips loading a Person record for every account on the list -- which the
    # index would otherwise pay for on every visit, purely to call .size.
    def count = missing_by_person.size

    def findings
      missing = missing_by_person
      return [] if missing.empty?

      Person.where(id: missing.keys).order(:callsign).map do |person|
        PositionSanityCheck::Finding.new(
          person_id: person.id, callsign: person.callsign, status: person.status,
          detail: missing[person.id].sort_by(&:last)
        )
      end
    end

    private

    # {person_id => [[position id, title], ...]}. Both sets are answered by
    # plucking the grant rows for the positions in question -- at most one row
    # per account per position -- rather than the correlated count subquery per
    # account that upstream ran.
    def missing_by_person
      missing = Hash.new { |hash, key| hash[key] = [] }

      collect_missing(Position.active.where(all_rangers: true), RANGER_STATUSES, missing)
      collect_missing(Position.active.where(new_user_eligible: true), USER_STATUSES, missing)

      missing
    end

    def collect_missing(positions, statuses, missing)
      titles = positions.pluck(:id, :title).to_h
      return if titles.empty?

      person_ids = Person.where(status: statuses).pluck(:id)
      return if person_ids.empty?

      held = PersonPosition.where(position_id: titles.keys).pluck(:person_id, :position_id).to_set

      person_ids.each do |person_id|
        titles.each do |position_id, title|
          next if held.include?([person_id, position_id])

          # Union, not append: a position flagged BOTH all_rangers and
          # new_user_eligible is reached by each of the two passes, and every
          # active or inactive account is in both status sets. Appending listed
          # it twice in the table and said "Granted Training and Granted
          # Training" in the results. Two live positions carry both flags.
          missing[person_id] |= [[position_id, title]]
        end
      end
    end

    # Granted by id, from the finding the reader is looking at. Position
    # titles repeat across teams, so a grant matched by title would be a
    # coin toss.
    def fix(finding)
      PersonPosition.add_ids_to_person(finding.person_id, finding.detail.map(&:first), reason)
      finding.detail.map { |_id, title| "Granted #{title}" }
    end
  end
end
