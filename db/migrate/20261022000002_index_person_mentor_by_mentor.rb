# frozen_string_literal: true

# Me/Person › Mentoring and the Alpha mentee reader look walks up by mentor,
# and no key starts with mentor_id, so each one scanned the table.
class IndexPersonMentorByMentor < ActiveRecord::Migration[8.1]
  def change
    add_index :person_mentor, [:mentor_id, :position_id], name: "index_person_mentor_on_mentor_id_and_position_id"
  end
end
