# frozen_string_literal: true

# The two sign-up page headers are the first editor text on position, and
# utf8mb3 refuses any four-byte character: one emoji in a header would fail
# the whole Position Records save. The table converts as a whole -- its other
# text is titles, tags and an email -- so schema.rb keeps one charset per
# table, as everywhere else. The conversion widens the two text columns to
# mediumtext.
#
# The way back fails while any header holds a four-byte character, rather
# than losing it.
class ConvertPositionToUtf8mb4 < ActiveRecord::Migration[8.1]
  def up
    execute "ALTER TABLE position CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci"
  end

  def down
    execute "ALTER TABLE position CONVERT TO CHARACTER SET utf8mb3 COLLATE utf8mb3_unicode_ci"
  end
end
