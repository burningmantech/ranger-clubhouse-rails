# frozen_string_literal: true

# People holding a team's basic positions who are not on the team. One finding
# per person per team; the positions that put them there are shown on the row.
#
# The mirror of Team Positions, and the same two filters apply for the same
# reason: an inactive position is the Deactivated Positions check's finding,
# and no one should be added to a switched-off team.
class PositionSanityCheck::TeamMembership < PositionSanityCheck::Base
  class << self
    def count = findings.size

    def findings
      rows = candidates
      members = memberships(rows)

      rows.reject { |row| members.include?([row[0], row[3]]) }
          .group_by { |row| [row[0], row[3]] }
          .map { |_pair, group| build(group) }
    end

    private

    # person id, callsign, status, team id, team title, position title.
    def candidates
      PersonPosition.joins(:person, position: :team)
                    .where(position: { active: true,
                                       team_category: Position::TEAM_CATEGORY_ALL_MEMBERS })
                    .where(team: { active: true })
                    .where.not(person: { status: Person::DEACTIVATED_STATUSES })
                    .order("person.callsign", "team.title", "position.title")
                    .pluck("person.id", "person.callsign", "person.status",
                           "team.id", "team.title", "position.title")
    end

    def memberships(rows)
      return Set.new if rows.empty?

      PersonTeam.where(person_id: rows.map(&:first).uniq, team_id: rows.map { _1[3] }.uniq)
                .pluck(:person_id, :team_id).to_set
    end

    # One person, one team, and every basic position of that team they hold.
    def build(group)
      row = group.first

      PositionSanityCheck::Finding.new(
        person_id: row[0], callsign: row[1], status: row[2],
        target_id: row[3], target_label: row[4],
        detail: group.map(&:last)
      )
    end

    def fix(finding)
      PersonTeam.add_person(finding.target_id, finding.person_id, reason)
      ["Added to #{finding.target_label}"]
    end
  end
end
