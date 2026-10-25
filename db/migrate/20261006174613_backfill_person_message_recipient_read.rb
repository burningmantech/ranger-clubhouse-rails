# frozen_string_literal: true

# Clubhouse 2 recorded "the recipient has read this" in `delivered`.
# ChangeMessageDeliveryMarking (20251031151449) added `recipient_read` without
# copying it, so every message read in Clubhouse 2 counted as unread again.
# Clubhouse 3 never writes `delivered`, so only a Clubhouse 2 read set it; a
# message since marked unread in Clubhouse 3 goes back to read (accepted
# 2026-10-06).
class BackfillPersonMessageRecipientRead < ActiveRecord::Migration[8.1]
  # The table as it is today, whatever the app model becomes.
  class MigrationPersonMessage < ActiveRecord::Base
    self.table_name = "person_message"
  end

  def up
    say_with_time "Copying person_message.delivered into recipient_read" do
      MigrationPersonMessage.where(delivered: true, recipient_read: false).update_all(recipient_read: true)
    end
  end

  def down
    # Nothing to undo: every row it touched was read in Clubhouse 2.
  end
end
