# frozen_string_literal: true

# Rails.cache moved to Redis (config/environments/production.rb), so Solid Cache's table,
# from 20260915190000_cache_schema.rb, has no reader left. The block makes the drop reversible.
class DropSolidCacheEntries < ActiveRecord::Migration[8.1]
  def change
    drop_table "solid_cache_entries", charset: "utf8mb4", collation: "utf8mb4_general_ci" do |t|
      t.binary "key", limit: 1024, null: false
      t.binary "value", limit: 536870912, null: false
      t.datetime "created_at", null: false
      t.integer "key_hash", limit: 8, null: false
      t.integer "byte_size", limit: 4, null: false
      t.index ["byte_size"], name: "index_solid_cache_entries_on_byte_size"
      t.index ["key_hash", "byte_size"], name: "index_solid_cache_entries_on_key_hash_and_byte_size"
      t.index ["key_hash"], name: "index_solid_cache_entries_on_key_hash", unique: true
    end
  end
end
