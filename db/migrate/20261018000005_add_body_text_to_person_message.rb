# frozen_string_literal: true

# Rich text in messages (messaging rework, slice 4): a body may now be the
# editor's HTML, and a full-text index on it would hold the tag and attribute
# words too, so "strong" or "href" would find every message with a bold word
# or a link. body_text holds the body's words alone (PersonMessage#body= keeps
# it), and the index moves onto it. Every row before this is plain text, so its
# words are its body.
#
# The default is for the release still serving while this migrates: it knows
# no body_text, and its INSERTs leave it out, which a NOT NULL column with no
# default refuses (review finding 4, 2026-10-18). The rows it writes then have
# an empty body_text until 20261018000007 copies their body in (deploy 2).
class AddBodyTextToPersonMessage < ActiveRecord::Migration[8.1]
  def up
    add_column :person_message, :body_text, :text, size: :medium, null: false, default: "", after: :body
    execute "UPDATE person_message SET body_text = body"
    remove_index :person_message, name: "index_person_message_on_subject_and_body"
    add_index :person_message, %i[subject body_text], type: :fulltext
  end

  def down
    remove_index :person_message, %i[subject body_text]
    add_index :person_message, %i[subject body], type: :fulltext
    remove_column :person_message, :body_text
  end
end
