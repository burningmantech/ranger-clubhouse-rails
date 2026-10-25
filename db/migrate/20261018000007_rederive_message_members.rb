# frozen_string_literal: true

# Slice 2 of the member model (.scratch/messaging-rework/member-model-plan.md):
# before the mailbox reads a one-to-one thread's member rows instead of its
# flags, every such row is derived from the flags again, which slice 1 kept
# answering every read.
#
# Slice 1's code wrote both models, but while it booted the code before it
# still served, writing flags alone: a thread it started has no members, and a
# Mark Read, Mark Unread or Archive it made is missing from its member row.
# So the one-to-one rows are deleted and made again by 20261018000006's rules
# (that file says them, the NULL-safe sender comparison too), in one
# transaction. The code running while this migrates is slice 1's, which writes
# both, so nothing it does is lost.
#
# A group thread's members are its only state, but that code wrote only their
# last_read_at, which slice 2 stops reading: the author's row a new group
# thread starts with, Mark Read and Mark Unread. So every group member's
# last_read_message_id is derived from its last_read_at again, by
# 20261018000006's rule (the newest row of the thread written by then), while
# that column is still there; a member whose last_read_at is NULL never read
# the thread. The author of a top is read through it at least, as slice 1's
# PersonMessage#add_members stamps them: the code before it set only their
# last_read_at, at the top's build, which a second's tick can put before the
# top's own time.
#
# The release before slice 1 knew no body_text either, so a message it saved
# while 20261018000005 had already run has an empty one. Its body is plain text
# (that release had no editor), so its words are its body, as 000005 copied
# them; slice 1's code, serving now, writes body_text itself.
#
# Run bin/rails messages:member_parity afterwards: it should find nothing.
class RederiveMessageMembers < ActiveRecord::Migration[8.1]
  def up
    transaction do
      execute <<~SQL
        DELETE m FROM person_message_member m
          JOIN person_message thread_top ON thread_top.id = m.person_message_id
         WHERE thread_top.`group` = 0
      SQL

      execute <<~SQL
        INSERT INTO person_message_member
          (person_message_id, person_id, last_read_at, last_read_message_id, archived, created_at)
        SELECT thread_id, person_id,
               CASE WHEN MAX(unread) = 0 THEN MAX(created_at)
                    WHEN MIN(IF(unread AND by_other, row_id, NULL)) IS NOT NULL
                      THEN MIN(IF(unread AND by_other, created_at, NULL)) - INTERVAL 1 SECOND
                    ELSE MAX(IF(by_other, created_at, NULL)) - INTERVAL 1 SECOND END,
               CASE WHEN MAX(unread) = 0 THEN MAX(row_id)
                    WHEN MIN(IF(unread AND by_other, row_id, NULL)) IS NOT NULL
                      THEN MIN(IF(unread AND by_other, row_id, NULL)) - 1
                    ELSE MAX(IF(by_other, row_id, NULL)) - 1 END,
               MAX(archived), MIN(top_created_at)
        FROM (
          SELECT party.thread_id, party.person_id, party.archived, party.created_at AS top_created_at,
                 thread_row.id AS row_id, thread_row.created_at,
                 CASE WHEN thread_row.sender_person_id = party.person_id THEN thread_row.sender_read = 0
                      WHEN thread_row.person_id = party.person_id THEN thread_row.recipient_read = 0
                      ELSE 0 END AS unread,
                 thread_row.sender_person_id IS NULL OR thread_row.sender_person_id <> party.person_id AS by_other
          FROM (
            SELECT id AS thread_id, person_id, created_at,
                   recipient_archived OR (sender_person_id <=> person_id AND sender_archived) AS archived
              FROM person_message WHERE reply_to_id IS NULL AND `group` = 0
            UNION ALL
            SELECT id, sender_person_id, created_at, sender_archived
              FROM person_message WHERE reply_to_id IS NULL AND `group` = 0 AND sender_person_id <> person_id
          ) party
          JOIN person_message thread_row
            ON thread_row.id = party.thread_id OR thread_row.reply_to_id = party.thread_id
        ) party_row
        GROUP BY thread_id, person_id
      SQL

      execute <<~SQL
        UPDATE person_message_member m
          JOIN person_message thread_top ON thread_top.id = m.person_message_id
           SET m.last_read_message_id = IF(m.last_read_at IS NULL, NULL, NULLIF(GREATEST(
                 COALESCE((SELECT MAX(thread_row.id) FROM person_message thread_row
                            WHERE (thread_row.id = m.person_message_id OR thread_row.reply_to_id = m.person_message_id)
                              AND thread_row.created_at <= m.last_read_at), 0),
                 IF(thread_top.sender_person_id = m.person_id, thread_top.id, 0)), 0))
         WHERE thread_top.`group` = 1
      SQL

      execute "UPDATE person_message SET body_text = body WHERE body_text = '' AND body <> ''"
    end

    # Every row was just replaced. On a copy of dev the statistics InnoDB had
    # not yet recounted turned the search's callsign lookup around: 585 reads
    # for the heaviest mailbox, 60 once analyzed.
    execute "ANALYZE TABLE person_message_member"
  end

  # Nothing to undo: slice 1's code reads the flags, which are still written.
  def down; end
end
