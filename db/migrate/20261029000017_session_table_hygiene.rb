# frozen_string_literal: true

# sessions is written by two hands: Authentication, one row per sign-in with
# the person, and the Rack session store, one row per visitor with no person.
# Both set session_id, so it is NOT NULL now. The sweeper of unchanged
# anonymous rows (ExpireAnonymousSessionsJob) reads by person and updated_at,
# so that pair is indexed in place of person alone, which it covers. The pair
# goes in first: the foreign key on person_id needs an index at every moment,
# and MariaDB refuses to drop the only one it has.
class SessionTableHygiene < ActiveRecord::Migration[8.1]
  def change
    change_column_null :sessions, :session_id, false
    add_index :sessions, [:person_id, :updated_at]
    remove_index :sessions, column: :person_id, name: "index_sessions_on_person_id"
  end
end
