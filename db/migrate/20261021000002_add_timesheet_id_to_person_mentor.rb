# frozen_string_literal: true

# An ART walk is one mentee shift with one mentor, so its person_mentor row
# names the mentee's timesheet entry. Alpha walks stay one row per mentor per
# year and leave the column NULL.
#
# timesheet_id is UNIQUE: one mentor per mentee shift. A MariaDB unique index
# treats every NULL as distinct, so the Alpha rows never collide on it.
#
# The person_id key gains timesheet_id so one mentor can walk one mentee on two
# shifts in a year. For an ART row the timesheet_id key already says more. For
# an Alpha row, whose timesheet_id is NULL, it now says nothing, since one NULL
# never matches another: the database no longer refuses a second Alpha row for
# the same mentor, mentee and year. PersonMentor's uniqueness validation holds
# that rule instead. The key keeps its name, which carries no column list.
#
# One ALTER TABLE each way (bulk: true): MariaDB DDL is not transactional, and
# separate statements would leave the table with no unique key between the
# drop and the re-add.
class AddTimesheetIdToPersonMentor < ActiveRecord::Migration[8.1]
  def up
    change_table :person_mentor, bulk: true do |t|
      t.bigint :timesheet_id, unsigned: true
      t.remove_index name: "person_id"
      t.index %i[person_id mentor_id mentor_year position_id timesheet_id], unique: true, name: "person_id"
      t.index :timesheet_id, unique: true
    end
  end

  # Refuses once an ART walk exists: the narrower key would reject a mentor who
  # walked one mentee on two shifts, and dropping the column would lose which
  # shift each row was for. Refuses too while two Alpha rows share the narrower
  # key -- only the model stopped them meanwhile -- naming the cause rather than
  # failing on a duplicate entry.
  def down
    if select_value("SELECT 1 FROM person_mentor WHERE timesheet_id IS NOT NULL LIMIT 1")
      raise ActiveRecord::IrreversibleMigration,
            "person_mentor holds ART walks keyed by timesheet; rolling back would lose which shift each was for"
    end
    if select_value("SELECT 1 FROM person_mentor GROUP BY person_id, mentor_id, mentor_year, position_id " \
                    "HAVING COUNT(*) > 1 LIMIT 1")
      raise ActiveRecord::IrreversibleMigration,
            "person_mentor holds duplicate Alpha rows; remove them before restoring the narrower unique key"
    end

    change_table :person_mentor, bulk: true do |t|
      t.remove_index :timesheet_id
      t.remove_index name: "person_id"
      t.index %i[person_id mentor_id mentor_year position_id], unique: true, name: "person_id"
      t.remove :timesheet_id
    end
  end
end
