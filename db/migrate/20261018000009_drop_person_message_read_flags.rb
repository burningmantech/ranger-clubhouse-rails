# frozen_string_literal: true

# Slice 3 of the member model (.scratch/messaging-rework/member-model-plan.md,
# ruled 2026-10-18): every thread's read and archive state is its
# person_message_member rows since slice 2, so the sender/recipient flags go,
# and with them delivered (no reader or writer since 8b05be61) and the member
# row's last_read_at (last_read_message_id replaced it, ruling D2).
#
# Deploy it only once the release before it, which ignores these columns
# (self.ignored_columns), is the one serving: a release that still names
# them, slice 2's, fails every message INSERT the moment they go (review
# finding 3, 2026-10-18). 20261018000008 dropped them on dev before that
# finding moved them here, so each is skipped where it is already gone.
#
# down puts the columns back where they were and derives them from the member
# rows, so slice 2's code, which writes them, runs again with every thread
# unread, Inboxed or Archived as the member rows say. Which rows of a thread
# read "New" by the flags may differ: a member row holds one place in the
# thread, not a flag per row.
class DropPersonMessageReadFlags < ActiveRecord::Migration[8.1]
  FLAGS = %i[delivered sender_read recipient_read sender_archived recipient_archived].freeze

  def up
    FLAGS.each { |flag| remove_column :person_message, flag, if_exists: true }
    remove_column :person_message_member, :last_read_at, if_exists: true
  end

  def down
    add_column :person_message, :delivered, :boolean, default: false, null: false, after: :body_text
    add_column :person_message, :sender_read, :boolean, default: true, null: false, after: :sender_type
    add_column :person_message, :recipient_read, :boolean, default: false, null: false, after: :sender_read
    add_column :person_message, :sender_archived, :boolean, default: false, null: false, after: :recipient_read
    add_column :person_message, :recipient_archived, :boolean, default: false, null: false, after: :sender_archived
    add_column :person_message_member, :last_read_at, :datetime, precision: nil, after: :person_id

    # Every row read, then unread where its recipient's member row has not
    # read it; a sent thread its sender marked unread (never read) flags the top.
    execute "UPDATE person_message SET recipient_read = TRUE"
    execute <<~SQL
      UPDATE person_message r
        JOIN person_message_member m ON m.person_message_id = COALESCE(r.reply_to_id, r.id) AND m.person_id = r.person_id
         SET r.recipient_read = FALSE
       WHERE r.`group` = 0 AND (r.sender_person_id IS NULL OR r.sender_person_id <> r.person_id)
         AND (m.last_read_message_id IS NULL OR r.id > m.last_read_message_id)
    SQL
    execute <<~SQL
      UPDATE person_message t
        JOIN person_message_member m ON m.person_message_id = t.id AND m.person_id = t.sender_person_id
         SET t.sender_read = FALSE
       WHERE t.`group` = 0 AND t.reply_to_id IS NULL AND m.last_read_message_id IS NULL
    SQL
    # One join each: a multi-table UPDATE changes a row once, however many
    # member rows match it.
    %w[person_id recipient_archived sender_person_id sender_archived].each_slice(2) do |party, flag|
      execute <<~SQL
        UPDATE person_message t
          JOIN person_message_member m ON m.person_message_id = t.id AND m.person_id = t.#{party}
           SET t.#{flag} = m.archived
         WHERE t.`group` = 0 AND t.reply_to_id IS NULL
      SQL
    end

    # The time of the newest row read: its newest reply read, else the top, or
    # just before the top when none is. The replies by reply_to_id alone: with
    # the top OR'd in, this one statement took 90 seconds on a copy of dev.
    execute <<~SQL
      UPDATE person_message_member m
        JOIN person_message t ON t.id = m.person_message_id
         SET m.last_read_at = COALESCE(
               (SELECT MAX(r.created_at) FROM person_message r
                 WHERE r.reply_to_id = m.person_message_id AND r.id <= m.last_read_message_id),
               IF(t.id <= m.last_read_message_id, t.created_at, t.created_at - INTERVAL 1 SECOND))
       WHERE m.last_read_message_id IS NOT NULL
    SQL
  end
end
