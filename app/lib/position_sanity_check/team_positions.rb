# frozen_string_literal: true

# Team members missing one of their team's basic positions. One finding per
# missing position, so a member short of two of them can be given one and not
# the other.
#
# Both the team and the position have to be active. Upstream checked neither
# here, which had it offering to grant a position of a switched-off team --
# the same membership the Deactivated Teams check is asking you to revoke.
class PositionSanityCheck::TeamPositions < PositionSanityCheck::Base
  class << self
    def count = findings.size

    def findings
      rows = candidates
      held = held_position_pairs(rows)
      rows.reject { |row| held.include?([row[0], row[5]]) }.map { |row| build(row) }
    end

    private

    # person id, callsign, status, team id, team title, position id, title.
    def candidates
      PersonTeam.joins(:person, team: :position)
                .where(team: { active: true })
                .where(position: { active: true,
                                   team_category: Position::TEAM_CATEGORY_ALL_MEMBERS })
                .where.not(person: { status: Person::DEACTIVATED_STATUSES })
                .order("person.callsign", "team.title", "position.title")
                .pluck("person.id", "person.callsign", "person.status",
                       "team.id", "team.title", "position.id", "position.title")
    end

    # Which of the candidate positions each candidate already holds. One query
    # for the whole page rather than the correlated left join upstream used,
    # which no ActiveRecord scope can express without raw SQL.
    def held_position_pairs(rows)
      return Set.new if rows.empty?

      PersonPosition.where(person_id: rows.map(&:first).uniq,
                           position_id: rows.map { _1[5] }.uniq)
                    .pluck(:person_id, :position_id).to_set
    end

    def build(row)
      PositionSanityCheck::Finding.new(
        person_id: row[0], callsign: row[1], status: row[2],
        target_id: row[5], target_label: row[6],
        group_label: row[4], group_id: row[3]
      )
    end

    def fix(finding)
      PersonPosition.add_ids_to_person(finding.person_id, [finding.target_id], reason)
      ["Granted #{finding.target_label}"]
    end
  end
end
