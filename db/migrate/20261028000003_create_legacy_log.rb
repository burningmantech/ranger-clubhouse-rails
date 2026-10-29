# frozen_string_literal: true

# The Clubhouse 1 audit log (`log`, 2008 to 2019) converted to Action Log
# form: one row per convertible `log` row, written only by
# `bin/rails legacy_log:convert` (LegacyLog::Conversion), which upserts on
# log_id so a rerun rewrites rather than duplicates. No ip, user_agent or
# updated_at: the first Clubhouse recorded neither. No message either (ruled
# 2026-10-28): what a row did is read from data. created_at is a DATETIME
# rather than the TIMESTAMP action_logs has: a TIMESTAMP column can pick up
# the server's implicit default and ON UPDATE rule, which schema.rb never
# shows, and a copied timestamp must stay what the log said.
class CreateLegacyLog < ActiveRecord::Migration[8.1]
  def change
    create_table :legacy_log, id: { type: :bigint, unsigned: true },
                              charset: "utf8mb4", collation: "utf8mb4_unicode_ci" do |t|
      t.bigint :log_id, null: false, unsigned: true
      t.integer :person_id, unsigned: true
      t.integer :target_person_id, unsigned: true
      t.string :event, limit: 191, null: false
      t.text :data, size: :long
      t.datetime :created_at, precision: nil, null: false
      t.index :log_id, unique: true
      t.index [:created_at, :id]
      t.index :event
      t.index [:person_id, :created_at]
      t.index [:target_person_id, :created_at]
    end
  end
end
