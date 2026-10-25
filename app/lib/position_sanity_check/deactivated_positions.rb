# frozen_string_literal: true

# Positions that have been switched off but are still granted. Rows group
# under the position, because that is what the repair revokes and what the
# reader decides about.
#
# Deactivated accounts are left out: they are the Deactivated Accounts check's
# finding, and revoking one position from an account that should have none is
# the wrong repair to reach for first.
class PositionSanityCheck::DeactivatedPositions < PositionSanityCheck::Base
  class << self
    private

    def scope
      PersonPosition.joins(:person, :position)
                    .preload(:person, :position)
                    .where(position: { active: false })
                    .where.not(person: { status: Person::DEACTIVATED_STATUSES })
                    .order("position.title", "person.callsign")
    end

    def build(row)
      PositionSanityCheck::Finding.new(
        person_id: row.person_id, callsign: row.person.callsign, status: row.person.status,
        target_id: row.position_id, target_label: row.position.title,
        group_id: row.position_id, group_label: row.position.title
      )
    end

    def fix(finding)
      PersonPosition.remove_ids_from_person(finding.person_id, [finding.target_id], reason)
      ["Revoked #{finding.target_label}"]
    end
  end
end
