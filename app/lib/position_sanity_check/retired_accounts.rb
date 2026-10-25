# frozen_string_literal: true

# Retired accounts holding more than the new-user set. A retired Ranger keeps
# the positions an auditor or prospective would have and nothing else.
class PositionSanityCheck::RetiredAccounts < PositionSanityCheck::Base
  class << self
    def count = scope(new_user_position_ids).count

    # The new-user set is derived once and threaded through both halves. Read
    # twice it was not only a second query -- an admin flipping a position's
    # new_user_eligible flag between them would have the flagged set and the
    # "positions beyond the new-user set" column disagreeing on one render.
    #
    # The extra positions are likewise read once for the whole page rather than
    # per row.
    def findings
      keep_ids = new_user_position_ids
      people = scope(keep_ids).to_a
      extra = extra_titles_by_person(people.map(&:id), keep_ids)

      people.map do |person|
        PositionSanityCheck::Finding.new(person_id: person.id, callsign: person.callsign,
                                         status: person.status, detail: extra[person.id])
      end
    end

    private

    def scope(keep_ids)
      # No new-user-eligible positions configured means every retired account
      # would be flagged for holding anything at all. Answer nothing instead:
      # the finding would be about the position table, not these accounts.
      return Person.none if keep_ids.empty?

      Person.where(status: Person::RETIRED)
            .where(id: PersonPosition.where.not(position_id: keep_ids).select(:person_id))
            .order(:callsign)
    end

    # Spelled the same way PersonPosition.reset_positions spells it, because
    # the repair calls that method: if the two ever disagree, this check flags
    # an account the repair cannot clear and the row returns on every reload.
    def new_user_position_ids = Position.where(active: true, new_user_eligible: true).pluck(:id)

    # {person_id => [title, ...]} -- the positions that put each account here,
    # so the reader can see what the repair is about to take away.
    def extra_titles_by_person(person_ids, keep_ids)
      titles = Hash.new { |hash, key| hash[key] = [] }
      return titles if person_ids.empty?

      Position.joins(:person_position)
              .where(person_position: { person_id: person_ids })
              .where.not(id: keep_ids)
              .order(:title)
              .pluck("person_position.person_id", :title)
              .each { |person_id, title| titles[person_id] << title }

      titles
    end

    # reset_positions grants the missing new-user positions before it revokes
    # the rest, so a refusal partway through used to leave the account with
    # MORE than it started with and nothing taken away. Base#settle wraps this
    # in a transaction, which is what makes the two halves one operation.
    def fix(finding)
      PersonPosition.reset_positions(finding.person_id, reason, Person::ADD_NEW_USER)
      ["Positions reset to the new-user set — #{finding.detail.to_sentence} revoked"]
    end
  end
end
