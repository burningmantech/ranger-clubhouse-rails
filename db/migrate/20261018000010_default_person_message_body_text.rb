# frozen_string_literal: true

# 20261018000005 adds body_text with an empty default since review finding 4
# (2026-10-18), so that the release still serving while it runs can save a
# message. Dev ran it before then, with no default; this gives dev the same
# column. Anywhere 000005 ran as it is now, the default is already there.
class DefaultPersonMessageBodyText < ActiveRecord::Migration[8.1]
  def change
    change_column_default :person_message, :body_text, from: nil, to: ""
  end
end
