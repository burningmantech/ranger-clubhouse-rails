# frozen_string_literal: true

# The Dirt - Shiny Penny position, which belongs to this year's first-year
# Rangers and to no one else. Two ways to be wrong, and the repair for a row
# is whichever way it is wrong -- this is the one check that both grants and
# revokes.
class PositionSanityCheck::ShinyPennies < PositionSanityCheck::Base
  class << self
    def count = findings.size

    # The two id sets are read once and passed down rather than memoized on the
    # class: these are class methods, so an ivar here would outlive the request
    # and answer the next reader with the last one's data.
    def findings
      alphas = alpha_person_ids
      holders = penny_holder_ids

      (missing_position(alphas, holders) + surplus_position(alphas, holders))
        .sort_by { _1.callsign.downcase }
    end

    def year = Current.year

    private

    # Walked Alpha this year and does not hold the position.
    #
    # The mentor year is read from person_mentor here too, not filled in with
    # the current year. What puts a row in this half is an Alpha timesheet, and
    # plenty of people have one without a mentor record -- stamping the season
    # into a column headed "Mentor year" asserted a record that does not exist.
    def missing_position(alphas, holders)
      findings_for(Person.where(status: Person::ACTIVE, id: alphas).where.not(id: holders),
                   holds_position: false)
    end

    # Holds the position and did not walk Alpha this year.
    def surplus_position(alphas, holders)
      findings_for(Person.where(id: holders).where.not(id: alphas), holds_position: true)
    end

    def findings_for(people, holds_position:)
      people = people.to_a
      mentored = mentor_years(people.map(&:id))

      people.map do |person|
        PositionSanityCheck::Finding.new(
          person_id: person.id, callsign: person.callsign, status: person.status,
          detail: { mentor_year: mentored[person.id], holds_position: }
        )
      end
    end

    def alpha_person_ids
      Timesheet.all.where_year("on_duty", year)
               .where(position_id: Position::ALPHA)
               .distinct.pluck(:person_id)
    end

    # Plucked rather than left as a relation: as a relation it was inlined as a
    # subquery three times per findings call, and person_position carries no
    # index on position_id, so each inlining was a full scan of the grant table.
    def penny_holder_ids
      PersonPosition.where(position_id: Position::DIRT_SHINY_PENNY).pluck(:person_id)
    end

    # The year each of them was mentored. Read ascending so the last row per
    # person -- the one to_h keeps -- is their newest. Nil for anyone never
    # mentored, which the table says rather than leaving the cell blank as
    # upstream did.
    def mentor_years(person_ids)
      return {} if person_ids.empty?

      PersonMentor.where(person_id: person_ids, position_id: Position::ALPHA)
                  .order(:mentor_year)
                  .pluck(:person_id, :mentor_year)
                  .to_h
    end

    def fix(finding)
      person_id = finding.person_id

      if finding.detail[:holds_position]
        PersonPosition.remove_ids_from_person(person_id, [Position::DIRT_SHINY_PENNY], reason)
        ["Not a Shiny Penny this year — position revoked"]
      else
        PersonPosition.add_ids_to_person(person_id, [Position::DIRT_SHINY_PENNY], reason)
        ["Shiny Penny for #{year} — position granted"]
      end
    end
  end
end
