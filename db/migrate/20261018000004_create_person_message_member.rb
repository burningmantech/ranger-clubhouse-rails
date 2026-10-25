# frozen_string_literal: true

# Shared group threads (messaging rework, slice 3): a message to several people,
# or to a Cadre or Delegation, is one thread everyone in it reads. Its rows are
# flagged `group`; each member, the sender included, has a row here holding what
# the sender/recipient flag pairs hold for a one-to-one thread.
#
# The name keeps the person_message prefix on purpose: RedactDatabase
# empties, and the dump skips the data of, every table it starts.
#
# A member's unread threads are found through their rows' replies, and no
# index led with reply_to_id, so every replies load was a full scan as well.
class CreatePersonMessageMember < ActiveRecord::Migration[8.1]
  def change
    add_column :person_message, :group, :boolean, default: false, null: false
    add_index :person_message, :reply_to_id

    create_table :person_message_member, id: :integer do |t|
      t.integer :person_message_id, null: false
      t.integer :person_id, null: false
      t.datetime :last_read_at, precision: nil
      t.boolean :archived, default: false, null: false
      t.datetime :created_at, precision: nil, null: false
      t.index %i[person_message_id person_id], unique: true
      t.index :person_id
    end
  end
end
