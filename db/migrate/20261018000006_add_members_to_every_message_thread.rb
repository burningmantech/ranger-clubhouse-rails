# frozen_string_literal: true

# Every thread gets person_message_member rows (slice 1 of the member model,
# .scratch/messaging-rework/member-model-plan.md, ruled 2026-10-18). Until
# slice 2 they are written alongside the sender/recipient flags, which every
# one-to-one read still uses. Nothing a person sees changes.
#
# - last_read_message_id (ruling D2): the newest message of the thread the
#   member has read. It replaces last_read_at once slice 2 reads it, so a
#   group member already holding a last read takes the newest row written by
#   then. Not indexed: it is compared with a row's id, never joined on.
# - (person_id, archived) replaces (person_id): the folders look a member's
#   threads up by both.
# - The backfill: a row per party of every one-to-one thread -- its recipient,
#   and its sender when that is someone else (a note to self has one row; a
#   broadcast, walk-up, team message or Clubhouse 2 import has no sender
#   person). Each is derived from that party's own flag on every row of the
#   thread (PersonMessage#read_flag: sender_read on a row they sent, else
#   recipient_read; a row that is neither counts as read):
#     nothing unread               -> read through the newest row
#     an unread row by someone else -> read up to just before the oldest one
#     only their own rows unread   -> up to just before the newest row by
#                                     someone else, or never read (Mark Unread)
#   so a thread is unread exactly when the flags say so. archived is the top's
#   own flag (no folder reads a reply's); a note to self takes either one, as
#   PersonMessage#archived? does. A thread that has members already (a group
#   thread) is skipped.
#
# The sender comparison is NULL-safe (<=>): a Clubhouse 2 import has no sender
# person and was merged with every flag set, so one its recipient moved back
# to the Inbox would otherwise make archived NULL, which the column refuses.
#
# MariaDB commits each DDL statement on its own, so a failure partway leaves
# the columns and indexes before it in place. Each is skipped when it is
# already there, and the two statements after them are safe to repeat (the
# insert skips threads that have members), so the migration can run again.
#
# Every column involved is DATETIME, so no value passes through the session
# clock. Rehearsed on a copy of dev (2026-10-18): 25,857 rows in a third of a
# second, every person's Unread, Inbox and Archived the same both ways
# (bin/rails messages:member_parity).
class AddMembersToEveryMessageThread < ActiveRecord::Migration[8.1]
  def up
    add_column :person_message_member, :last_read_message_id, :integer, if_not_exists: true
    add_index :person_message_member, %i[person_id archived], if_not_exists: true
    remove_index :person_message_member, :person_id, if_exists: true

    execute <<~SQL
      UPDATE person_message_member m
         SET m.last_read_message_id = (
               SELECT MAX(thread_row.id) FROM person_message thread_row
                WHERE (thread_row.id = m.person_message_id OR thread_row.reply_to_id = m.person_message_id)
                  AND thread_row.created_at <= m.last_read_at)
       WHERE m.last_read_at IS NOT NULL
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
        WHERE NOT EXISTS (SELECT 1 FROM person_message_member m WHERE m.person_message_id = party.thread_id)
      ) party_row
      GROUP BY thread_id, person_id
    SQL
  end

  # Today's main reads every member row a person has as a group thread's, so
  # the one-to-one rows go before it runs again.
  def down
    execute <<~SQL
      DELETE m FROM person_message_member m
        JOIN person_message thread_top ON thread_top.id = m.person_message_id
       WHERE thread_top.`group` = 0
    SQL
    add_index :person_message_member, :person_id
    remove_index :person_message_member, %i[person_id archived]
    remove_column :person_message_member, :last_read_message_id
  end
end
