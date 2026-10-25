# frozen_string_literal: true

# person_mentor.notes takes what a trainer types on the ART Mentor Assignment
# roster, the first page to write it, and utf8mb3 refuses any four-byte
# character: one emoji in a note failed the whole shift's save. The table
# converts as a whole -- notes is its only free text -- so schema.rb keeps one
# charset per table, as everywhere else.
#
# The way back fails while any note holds a four-byte character, rather than
# losing it.
class ConvertPersonMentorToUtf8mb4 < ActiveRecord::Migration[8.1]
  def up
    execute "ALTER TABLE person_mentor CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci"
  end

  def down
    execute "ALTER TABLE person_mentor CONVERT TO CHARACTER SET utf8mb3 COLLATE utf8mb3_general_ci"
  end
end
