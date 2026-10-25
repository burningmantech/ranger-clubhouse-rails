# frozen_string_literal: true

# Accounts that are out -- bonked, deceased, dismissed, past prospective,
# resigned, uberbonked -- still holding positions, team membership, or
# permissions.
class PositionSanityCheck::DeactivatedAccounts < PositionSanityCheck::Base
  # What each of the three grant tables is called on the row, in the order the
  # row names them.
  HOLDINGS = { "positions" => PersonPosition,
               "team membership" => PersonTeam,
               "permissions" => PersonRole }.freeze

  class << self
    # The three "what do they still hold" lookups are answered once for the
    # whole page rather than per row: three queries, not three per finding.
    def findings
      people = scope.to_a
      held = held_by_person(people.map(&:id))

      people.map do |person|
        PositionSanityCheck::Finding.new(person_id: person.id, callsign: person.callsign,
                                         status: person.status, detail: held[person.id])
      end
    end

    private

    def scope
      deactivated = Person.where(status: Person::DEACTIVATED_STATUSES)

      deactivated.where(id: PersonPosition.select(:person_id))
                 .or(deactivated.where(id: PersonTeam.select(:person_id)))
                 .or(deactivated.where(id: PersonRole.select(:person_id)))
                 .order(:callsign)
    end

    # {person_id => ["positions", "permissions"]}. Named on the row because
    # upstream showed nothing here and revoked all three regardless, so the
    # reader could not tell a stray permission from a full set of positions.
    def held_by_person(person_ids)
      held = Hash.new { |hash, key| hash[key] = [] }
      return held if person_ids.empty?

      HOLDINGS.each do |label, model|
        model.where(person_id: person_ids).distinct.pluck(:person_id).each { held[_1] << label }
      end

      held
    end

    def fix(finding)
      person_id = finding.person_id
      PersonPosition.reset_positions(person_id, reason, Person::REMOVE_ALL)
      remove_every_team(person_id)
      PersonRole.remove_all_from_person(person_id, reason)

      ["Revoked #{finding.detail.to_sentence}"]
    end

    # Team ids come from person_team itself, not from
    # PersonTeam.remove_all_from_person.
    #
    # That method walks find_all_teams_for_person, which INNER JOINs team, so a
    # membership row pointing at a team that no longer exists is invisible to
    # it -- while this check reads person_team directly and does see the row.
    # Going through it left the finding standing after a repair that reported
    # success, which reads to the admin as a page that cannot count. The dev
    # database has two such rows today.
    def remove_every_team(person_id)
      PersonTeam.where(person_id:).pluck(:team_id).each do |team_id|
        PersonTeam.remove_person(team_id, person_id, reason)
      end
    end
  end
end
