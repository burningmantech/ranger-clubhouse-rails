# frozen_string_literal: true

# Mailbox search (messaging rework, slice 2): PersonMessage.search_for_person
# matches a person's messages by MATCH(subject, body) AGAINST (... IN BOOLEAN
# MODE), which InnoDB answers only from a FULLTEXT index on exactly those
# columns. The first FULLTEXT index on a table rebuilds it (InnoDB adds its
# hidden FTS_DOC_ID column).
class AddFulltextIndexToPersonMessage < ActiveRecord::Migration[8.1]
  def change
    add_index :person_message, %i[subject body], type: :fulltext
  end
end
