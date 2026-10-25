# frozen_string_literal: true

# person_mentor has only ever held Alpha walks. Other mentee positions are to
# share the table, so each row now names the position it was walked for. The
# default is Position::ALPHA, written as the literal 1 so the migration does not
# depend on app code that may change. It backfills every existing row and is
# kept.
#
# The unique key widens to include the position so one mentor can walk one
# person in two positions in a year. Its name carries no column list and stays.
#
# One ALTER TABLE each way (bulk: true): MariaDB DDL is not transactional, and
# separate statements would leave the table with no unique key between the drop
# and the re-add, and a half-applied migration that cannot be re-run if the
# re-add failed.
class AddPositionIdToPersonMentor < ActiveRecord::Migration[8.1]
  def up
    change_table :person_mentor, bulk: true do |t|
      t.bigint :position_id, unsigned: true, null: false, default: 1
      t.remove_index %i[person_id mentor_id mentor_year], name: "person_id"
      t.index %i[person_id mentor_id mentor_year position_id], unique: true, name: "person_id"
    end
  end

  # Refuses once another position has rows: the narrower key would reject a
  # mentor who walked one person in two positions that year, and dropping the
  # column would turn every such walk into an Alpha walk.
  def down
    if select_value("SELECT 1 FROM person_mentor WHERE position_id <> 1 LIMIT 1")
      raise ActiveRecord::IrreversibleMigration,
            "person_mentor holds walks for positions other than Alpha; rolling back would fold them into Alpha"
    end

    change_table :person_mentor, bulk: true do |t|
      t.remove_index name: "person_id"
      t.index %i[person_id mentor_id mentor_year], unique: true, name: "person_id"
      t.remove :position_id
    end
  end
end
