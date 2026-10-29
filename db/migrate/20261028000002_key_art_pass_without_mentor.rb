# frozen_string_literal: true

# A pass recorded with no mentor (20261028000001) is a row whose mentor_id is
# NULL, and MariaDB never matches one NULL against another in a unique key, so
# the (timesheet_id, mentor_id) key let two saves racing on one mentee shift
# each write one. mentor_key reads 0 for that NULL and the key moves onto it:
# the database refuses the second row, and the save reports a conflict
# (ArtMentoring::Assignment). An Alpha walk's NULL timesheet_id keeps it out of
# the key, as before.
class KeyArtPassWithoutMentor < ActiveRecord::Migration[8.1]
  def change
    add_column :person_mentor, :mentor_key, :virtual, type: :bigint, unsigned: true, as: "IFNULL(mentor_id, 0)",
                                                      stored: true
    add_index :person_mentor, %i[timesheet_id mentor_key], unique: true
    remove_index :person_mentor, %i[timesheet_id mentor_id], unique: true
  end
end
