# frozen_string_literal: true

# A team's roster by team: the only index led with person_id, so every read of
# a team's members (Team#members, and a team thread's roster on each render and
# reply, PersonMessage#current_team_memberships and #sync_team_members!)
# scanned all of person_team. Covering, as the thread reads both columns.
class AddTeamIdIndexToPersonTeam < ActiveRecord::Migration[8.1]
  def change
    add_index :person_team, %i[team_id person_id]
  end
end
