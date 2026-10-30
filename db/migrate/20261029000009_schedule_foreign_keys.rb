# frozen_string_literal: true

# Keys to slot, position, team, role, timesheet, pod and timesheet_missing.
# RESTRICT where the parent's model or its management module (Slot, Position,
# Team, Role, Timesheet, PositionManagement, TeamManagement) already removes
# the child; SET NULL on the optional links a child outlives (a timesheet's
# slot, a slot's trainer or trainee session, a position's parent).
#
# Left without a key, on purpose: slot.training_id (0 means none, read by
# Scheduling::SlotCopier), timesheet_missing.position_id (8 requests name a
# deleted position), person_position_log and person_team_log (the grant
# history PositionManagement keeps), radio_log and person_message's position
# and team columns (history), and person_mentor.timesheet_id: an ART walk
# outlives its deleted entry and reads "Shift deleted" (ruling 2026-10-21),
# and a NULL there would make it an Alpha walk.
#
# Rows already naming a parent that is gone go first: statuses and credits of
# deleted slots and positions are removed, as the parent's deletion would have
# removed them; the optional links are set NULL. Down drops the keys and puts
# the column types back; the removed rows do not come back.
class ScheduleForeignKeys < ActiveRecord::Migration[8.1]
  KEYS = [
    { table: "person_slot", column: "slot_id", parent: "slot", on_delete: :restrict,
      was: { type: :bigint, unsigned: true, null: false } },
    { table: "trainee_status", column: "slot_id", parent: "slot", on_delete: :restrict,
      was: { type: :bigint, unsigned: true, null: false } },
    { table: "trainer_status", column: "slot_id", parent: "slot", on_delete: :restrict,
      was: { type: :bigint, unsigned: true, null: false } },
    { table: "trainer_status", column: "trainer_slot_id", parent: "slot", on_delete: :restrict,
      was: { type: :bigint, unsigned: true, null: false } },
    { table: "trainee_note", column: "slot_id", parent: "slot", on_delete: :restrict,
      was: { type: :integer, unsigned: false, null: false } },
    { table: "timesheet", column: "slot_id", parent: "slot", on_delete: :nullify,
      was: { type: :bigint, unsigned: false, null: true } },
    { table: "pod", column: "slot_id", parent: "slot", on_delete: :nullify,
      was: { type: :integer, unsigned: false, null: true } },
    { table: "slot", column: "trainee_slot_id", parent: "slot", on_delete: :nullify,
      was: { type: :bigint, unsigned: true, null: true } },
    { table: "slot", column: "trainer_slot_id", parent: "slot", on_delete: :nullify,
      was: { type: :bigint, unsigned: true, null: true } },
    { table: "slot", column: "parent_signup_slot_id", parent: "slot", on_delete: :nullify,
      was: { type: :integer, unsigned: false, null: true } },
    { table: "survey_answer", column: "slot_id", parent: "slot", on_delete: :nullify,
      was: { type: :bigint, unsigned: false, null: true } },
    { table: "slot", column: "position_id", parent: "position", on_delete: :restrict,
      was: { type: :bigint, unsigned: true, null: false } },
    { table: "person_position", column: "position_id", parent: "position", on_delete: :restrict,
      was: { type: :bigint, unsigned: true, null: false } },
    { table: "position_role", column: "position_id", parent: "position", on_delete: :restrict,
      was: { type: :integer, unsigned: false, null: false } },
    { table: "position_lineup_member", column: "position_id", parent: "position", on_delete: :restrict,
      was: { type: :integer, unsigned: false, null: false } },
    { table: "person_mentor", column: "position_id", parent: "position", on_delete: :restrict,
      was: { type: :bigint, unsigned: true, null: false } },
    { table: "timesheet", column: "position_id", parent: "position", on_delete: :restrict,
      was: { type: :bigint, unsigned: true, null: false } },
    { table: "position_credit", column: "position_id", parent: "position", on_delete: :restrict,
      was: { type: :integer, unsigned: false, null: false } },
    { table: "person_online_course", column: "position_id", parent: "position", on_delete: :restrict,
      was: { type: :integer, unsigned: false, null: false } },
    { table: "online_course", column: "position_id", parent: "position", on_delete: :restrict,
      was: { type: :integer, unsigned: false, null: false } },
    { table: "bmid_title", column: "position_id", parent: "position", on_delete: :restrict,
      was: { type: :bigint, unsigned: true, null: false } },
    { table: "person_award", column: "position_id", parent: "position", on_delete: :restrict,
      was: { type: :integer, unsigned: false, null: true } },
    { table: "position", column: "parent_position_id", parent: "position", on_delete: :nullify,
      was: { type: :integer, unsigned: false, null: true } },
    { table: "position", column: "training_position_id", parent: "position", on_delete: :nullify,
      was: { type: :bigint, unsigned: true, null: true } },
    { table: "survey", column: "position_id", parent: "position", on_delete: :nullify,
      was: { type: :integer, unsigned: false, null: true } },
    { table: "survey", column: "mentoring_position_id", parent: "position", on_delete: :nullify,
      was: { type: :integer, unsigned: false, null: true } },
    { table: "timesheet", column: "desired_position_id", parent: "position", on_delete: :nullify,
      was: { type: :integer, unsigned: false, null: true } },
    { table: "person_team", column: "team_id", parent: "team", on_delete: :restrict,
      was: { type: :integer, unsigned: false, null: false } },
    { table: "team_manager", column: "team_id", parent: "team", on_delete: :restrict,
      was: { type: :integer, unsigned: false, null: false } },
    { table: "team_role", column: "team_id", parent: "team", on_delete: :restrict,
      was: { type: :integer, unsigned: false, null: false } },
    { table: "position", column: "team_id", parent: "team", on_delete: :restrict,
      was: { type: :integer, unsigned: false, null: true } },
    { table: "person_award", column: "team_id", parent: "team", on_delete: :restrict,
      was: { type: :integer, unsigned: false, null: true } },
    { table: "person_role", column: "role_id", parent: "role", on_delete: :restrict,
      was: { type: :bigint, unsigned: true, null: false } },
    { table: "position_role", column: "role_id", parent: "role", on_delete: :restrict,
      was: { type: :integer, unsigned: false, null: false } },
    { table: "team_role", column: "role_id", parent: "role", on_delete: :restrict,
      was: { type: :integer, unsigned: false, null: false } },
    { table: "timesheet_note", column: "timesheet_id", parent: "timesheet", on_delete: :restrict,
      was: { type: :integer, unsigned: false, null: false } },
    { table: "person_pod", column: "timesheet_id", parent: "timesheet", on_delete: :nullify,
      was: { type: :integer, unsigned: false, null: true } },
    { table: "person_pog", column: "timesheet_id", parent: "timesheet", on_delete: :nullify,
      was: { type: :integer, unsigned: false, null: true } },
    { table: "person_pod", column: "pod_id", parent: "pod", on_delete: :restrict,
      was: { type: :integer, unsigned: false, null: false } },
    { table: "pod", column: "mentor_pod_id", parent: "pod", on_delete: :nullify,
      was: { type: :integer, unsigned: false, null: true } },
    { table: "timesheet_missing_note", column: "timesheet_missing_id", parent: "timesheet_missing", on_delete: :restrict,
      was: { type: :integer, unsigned: false, null: false } }
  ].freeze

  def up
    delete_orphans "trainee_status", "slot_id", "slot"          # 182 rows on 2026-10-29
    delete_orphans "person_team", "team_id", "team"             # 2
    delete_orphans "position_credit", "position_id", "position" # 231
    nullify_orphans "timesheet", "slot_id", "slot"              # 36
    nullify_orphans "slot", "trainee_slot_id", "slot"           # 47
    nullify_orphans "person_pod", "timesheet_id", "timesheet"   # 4
    nullify_orphans "person_pog", "timesheet_id", "timesheet"   # 3

    KEYS.each do |key|
      retype_to_parent(key)
      add_foreign_key key[:table], key[:parent], column: key[:column], on_delete: key[:on_delete]
    end
  end

  def down
    KEYS.reverse_each do |key|
      remove_foreign_key key[:table], column: key[:column]
      drop_key_index(key)
      restore_type(key)
    end
  end

  private

  # The child column takes the parent key's exact type (MariaDB refuses a key
  # between types that differ), keeping its own nullability.
  def retype_to_parent(key)
    parent_id = connection.columns(key[:parent]).find { |c| c.name == "id" }
    change_column key[:table], key[:column], parent_id.sql_type.start_with?("bigint") ? :bigint : :integer,
                  unsigned: parent_id.sql_type.include?("unsigned"),
                  null: connection.columns(key[:table]).find { |c| c.name == key[:column] }.null
  end

  def restore_type(key)
    change_column key[:table], key[:column], key[:was][:type], unsigned: key[:was][:unsigned], null: key[:was][:null]
  end

  # MariaDB indexes a key column that had no index, under the key's name; the
  # key's removal leaves it behind.
  def drop_key_index(key)
    index = connection.indexes(key[:table]).find { |i| i.columns == [key[:column]] && i.name.start_with?("fk_rails_") }
    remove_index key[:table], name: index.name if index
  end

  def delete_orphans(table, column, parent)
    execute "DELETE child FROM #{table} child LEFT JOIN #{parent} p ON p.id = child.#{column} WHERE p.id IS NULL"
  end

  def nullify_orphans(table, column, parent)
    execute "UPDATE #{table} child LEFT JOIN #{parent} p ON p.id = child.#{column} " \
            "SET child.#{column} = NULL WHERE child.#{column} IS NOT NULL AND p.id IS NULL"
  end
end
