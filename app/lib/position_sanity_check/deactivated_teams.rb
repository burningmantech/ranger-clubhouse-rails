# frozen_string_literal: true

# Teams that have been switched off but still have members. Rows group under
# the team.
#
# The repair revokes the team's positions as well as the membership, which is
# what upstream does: leaving the positions behind would only move the person
# to the Deactivated Positions check.
class PositionSanityCheck::DeactivatedTeams < PositionSanityCheck::Base
  class << self
    private

    def scope
      PersonTeam.joins(:person, :team)
                .preload(:person, :team)
                .where(team: { active: false })
                .where.not(person: { status: Person::DEACTIVATED_STATUSES })
                .order("team.title", "person.callsign")
    end

    def build(row)
      PositionSanityCheck::Finding.new(
        person_id: row.person_id, callsign: row.person.callsign, status: row.person.status,
        target_id: row.team_id, target_label: row.team.title,
        group_id: row.team_id, group_label: row.team.title
      )
    end

    # Only the member positions come away with the membership.
    #
    # TeamMembershipReport::REVOCABLE_CATEGORIES is the app's single answer to
    # "what does leaving this team cost" -- Roster Management and Bulk Teams
    # both ask it rather than respelling the categories. Upstream took every
    # position of the team, which includes the Public ones: those are open to
    # the whole organization and are held by hundreds of people who were never
    # on the team, so revoking them here would take away access no other path
    # in the app treats as team-owned.
    def fix(finding)
      position_ids = Position.where(team_id: finding.target_id,
                                    team_category: TeamMembershipReport::REVOCABLE_CATEGORIES)
                             .pluck(:id)
      PersonPosition.remove_ids_from_person(finding.person_id, position_ids, reason)
      PersonTeam.remove_person(finding.target_id, finding.person_id, reason)

      ["Removed from #{finding.target_label} and its member positions revoked"]
    end
  end
end
