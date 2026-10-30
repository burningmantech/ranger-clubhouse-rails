# frozen_string_literal: true

# sessions is written by two hands: Authentication, one row per sign-in with
# the person, and the Rack session store, one row per visitor with no person.
# Both set session_id, so it is NOT NULL now, and updated_at gets the index the
# sweeper of idle anonymous rows (ExpireAnonymousSessionsJob) reads by.
class SessionTableHygiene < ActiveRecord::Migration[8.1]
  def change
    change_column_null :sessions, :session_id, false
    add_index :sessions, :updated_at
  end
end
