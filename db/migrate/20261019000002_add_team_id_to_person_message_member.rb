# frozen_string_literal: true

# Which team put a person in a thread (.scratch/team-messaging/PRD.md): set
# when the roster was read, at the top's send or at a later reply
# (PersonMessage#sync_team_members!). NULL for a person named directly, and for
# both parties of a one-to-one thread. Additive, so the release serving while it
# runs is unaffected: its inserts name their columns.
class AddTeamIdToPersonMessageMember < ActiveRecord::Migration[8.1]
  def change
    add_column :person_message_member, :team_id, :integer
    add_index :person_message_member, :team_id
  end
end
