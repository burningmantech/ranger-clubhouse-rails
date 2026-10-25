# frozen_string_literal: true

# Slice 3 of the member model (.scratch/messaging-rework/member-model-plan.md,
# ruled 2026-10-18): no query reads person_message by person_id since slice 2
# (EXPLAIN of every mailbox query on a copy of dev, 2026-10-18), so
# person_message_person_id_reply_to_id_index goes, and (person_id, created_at)
# stays as the person column's index. An index is no column a release names,
# so this is safe while slice 2's code still serves.
#
# This migration dropped the read and archive flags too until review finding
# 3 (2026-10-18): it ran while slice 2's code, which writes them, still
# served, so every message INSERT and flag write of that release failed. They
# go in 20261018000009, after a release that ignores them is serving. Dev ran
# the first version, which dropped them, so 000009 skips what is gone.
class DropPersonMessagePersonIdReplyToIdIndex < ActiveRecord::Migration[8.1]
  def change
    remove_index :person_message, %i[person_id reply_to_id], name: "person_message_person_id_reply_to_id_index"
  end
end
