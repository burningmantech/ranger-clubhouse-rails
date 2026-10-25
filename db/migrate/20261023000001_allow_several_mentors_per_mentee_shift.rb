# frozen_string_literal: true

# A mentee may walk with more than one mentor on one shift: one person_mentor
# row per mentor, every one naming the mentee's timesheet entry. The unique key
# on timesheet_id alone gains mentor_id. Alpha rows leave timesheet_id NULL and
# are held by the model either way.
class AllowSeveralMentorsPerMenteeShift < ActiveRecord::Migration[8.1]
  def change
    change_table :person_mentor, bulk: true do |t|
      t.remove_index :timesheet_id, unique: true
      t.index %i[timesheet_id mentor_id], unique: true
    end
  end
end
