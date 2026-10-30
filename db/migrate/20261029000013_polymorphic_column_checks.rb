# frozen_string_literal: true

# Two "which one of these" column sets get the rule their models apply written
# into the table: an award names exactly one of an award, a position or a team
# (every row did), and a message from a person or a team names that sender
# (every row did; nothing on dev was ever sent as a team). The sender rule is
# two checks, one clause each: MariaDB drops the outer parentheses of a stored
# "(a) AND (b)", and the schema dump then no longer loads.
#
# access_document_changes.table_name said "access_document" on all 89,615 rows
# and nothing read it, so it goes; down puts it back with that value.
class PolymorphicColumnChecks < ActiveRecord::Migration[8.1]
  def change
    add_check_constraint :person_award,
                         "(award_id IS NOT NULL) + (position_id IS NOT NULL) + (team_id IS NOT NULL) = 1",
                         name: "person_award_one_target"
    add_check_constraint :person_message, "sender_type <> 'person' OR sender_person_id IS NOT NULL",
                         name: "person_message_person_sender_named"
    add_check_constraint :person_message, "sender_type <> 'team' OR sender_team_id IS NOT NULL",
                         name: "person_message_team_sender_named"
    remove_column :access_document_changes, :table_name, :string, limit: 32, null: false, default: "access_document"
  end
end
