# frozen_string_literal: true

# Ten indexes are a left prefix of another index on the same table, so the
# planner never needs them and every write pays for them twice; the one on
# action_logs duplicates the primary key on the largest table in the database.
#
# Six are added where a page reads a table by a column no index leads with:
# team_manager by person (and one row per person and team), the membership
# history logs by person, team and position with the open rows picked out by
# left_on, and an access document's change log by its record.
class PruneAndAddIndexes < ActiveRecord::Migration[8.1]
  def change
    remove_index :timesheet, column: :person_id, name: "person_id"
    remove_index :timesheet, column: :position_id, name: "position_id"
    remove_index :timesheet, column: :on_duty, name: "timesheet_on_duty_index"
    remove_index :person_slot, column: :slot_id, name: "slot_id"
    remove_index :person_asset, column: :person_id, name: "person_id"
    remove_index :person_certification, column: :person_id, name: "person_certification_person_id_index"
    remove_index :person_banner, column: :person_id, name: "person_banner_person_id_index"
    remove_index :pod, column: :slot_id, name: "pod_slot_id_index"
    remove_index :radio_log, column: :radio_id, name: "radio_id"
    remove_index :position_credit, column: :start_year, name: "position_credit_start_year_index"
    remove_index :action_logs, column: :id, name: "secondary_id_idx"

    add_index :team_manager, [:person_id, :team_id], unique: true
    add_index :person_position_log, [:person_id, :left_on]
    add_index :person_position_log, [:position_id, :left_on]
    add_index :person_team_log, [:person_id, :left_on]
    add_index :person_team_log, [:team_id, :left_on]
    add_index :access_document_changes, :record_id
  end
end
