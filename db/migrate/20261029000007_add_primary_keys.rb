# frozen_string_literal: true

# Six join tables had a unique index and no primary key, so replication had to
# scan for a row to apply a change to it. Each unique index becomes the primary
# key; person_motd's index was not unique, and its rows have no duplicate pairs.
# position_lineup_member stays unique on position alone: a position sits in one
# lineup, and the model's key follows (PositionLineupMember.primary_key).
# person_event keys (person_id, year), the order PersonEvent.primary_key gives;
# a year-only read still has (year, mvr_eligible).
class AddPrimaryKeys < ActiveRecord::Migration[8.1]
  KEYS = [
    { table: "person_event", key: "person_id, year",
      index: "person_event_year_person_id_unique", columns: "year, person_id", unique: true },
    { table: "person_motd", key: "person_id, motd_id",
      index: "person_motd_person_id_motd_id_index", columns: "person_id, motd_id", unique: false },
    { table: "person_role", key: "person_id, role_id",
      index: "person_id_and_role_id", columns: "person_id, role_id", unique: true },
    { table: "position_role", key: "position_id, role_id",
      index: "position_role_position_id_role_id_unique", columns: "position_id, role_id", unique: true },
    { table: "team_role", key: "team_id, role_id",
      index: "team_role_team_id_role_id_unique", columns: "team_id, role_id", unique: true },
    { table: "position_lineup_member", key: "position_id",
      index: "position_lineup_member_position_id_unique", columns: "position_id", unique: true }
  ].freeze

  def up
    KEYS.each do |k|
      execute "ALTER TABLE #{k[:table]} DROP INDEX #{k[:index]}, ADD PRIMARY KEY (#{k[:key]})"
    end
  end

  def down
    KEYS.each do |k|
      execute "ALTER TABLE #{k[:table]} DROP PRIMARY KEY, " \
              "ADD #{k[:unique] ? "UNIQUE " : ""}INDEX #{k[:index]} (#{k[:columns]})"
    end
  end
end
