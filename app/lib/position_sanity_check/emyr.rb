# frozen_string_literal: true

# Event Management Year Round handed out directly, to someone who holds no
# position and belongs to no team that grants it.
#
# The permission is meant to arrive through a position or a team, so a direct
# grant survives long after the reason for it has gone.
class PositionSanityCheck::Emyr < PositionSanityCheck::Base
  class << self
    private

    # Upstream left-joined the granting positions and teams and looked for
    # nulls, in two conditionally-built joins that each silently did nothing
    # when their id list came back empty. NOT IN over the same two sets says
    # it once and is right when a set is empty.
    def scope
      Person.where(id: PersonRole.where(role_id: Role::EVENT_MANAGEMENT).select(:person_id))
            # Deactivated accounts are the Deactivated Accounts check's finding,
            # as they are for every other revoke check here. Without this a
            # bonked account with a direct grant is a finding twice, the board's
            # total counts it twice, and repairing it here takes the permission
            # while leaving the positions and teams that put it on the other list.
            .where.not(status: Person::DEACTIVATED_STATUSES)
            .where.not(id: PersonPosition.where(position_id: granting_position_ids)
                                         .select(:person_id))
            .where.not(id: PersonTeam.where(team_id: granting_team_ids).select(:person_id))
            .order(:callsign)
    end

    def granting_position_ids
      PositionRole.where(role_id: Role::EVENT_MANAGEMENT).select(:position_id)
    end

    def granting_team_ids
      TeamRole.where(role_id: Role::EVENT_MANAGEMENT).select(:team_id)
    end

    def build(person)
      PositionSanityCheck::Finding.new(person_id: person.id, callsign: person.callsign,
                                       status: person.status)
    end

    def fix(finding)
      PersonRole.remove_ids_from_person(finding.person_id, [Role::EVENT_MANAGEMENT], reason)
      ["Event Management Year Round revoked"]
    end
  end
end
