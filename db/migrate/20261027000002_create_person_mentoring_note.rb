# frozen_string_literal: true

# Cadre notes (ruled 2026-10-27): what an ART's mentoring cadre notes about a
# mentee, tied to no mentor, shift, year or ART, and shown on every roster the
# mentee is on. person_id is the mentee, written_by_id who wrote the note.
# Add-only, so no updated_at.
#
# utf8mb4 by name, as person_mentor's notes are: the server default is not a
# promise, and a note may hold an emoji.
class CreatePersonMentoringNote < ActiveRecord::Migration[8.1]
  def change
    create_table :person_mentoring_note, id: { type: :bigint, unsigned: true },
                                         charset: "utf8mb4", collation: "utf8mb4_unicode_ci" do |t|
      t.bigint :person_id, null: false, unsigned: true
      t.bigint :written_by_id, null: false, unsigned: true
      t.text :notes, null: false
      t.datetime :created_at, precision: nil, null: false
      t.index :person_id
      t.index :written_by_id
    end
  end
end
