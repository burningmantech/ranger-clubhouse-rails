# frozen_string_literal: true

# ExpireBroadcastMessagesJob looks for expired broadcasts every night; only
# broadcasts carry an expires_at, so the index is small and spares it a scan
# of the whole table.
class IndexPersonMessageExpiresAt < ActiveRecord::Migration[8.1]
  def change
    add_index :person_message, :expires_at
  end
end
