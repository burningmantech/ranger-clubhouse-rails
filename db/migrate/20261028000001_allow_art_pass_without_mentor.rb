# frozen_string_literal: true

# An ART pass may be recorded with no mentor (owner, 2026-10-28): its walk is
# one person_mentor row whose mentor_id is NULL. PersonMentor allows the NULL
# only on an ART walk's pass, and every Alpha reader selects position_id =
# Alpha, so none of them meets such a row.
#
# down guards db:rollback only. An image rolled back past this change draws a
# mentor-less pass as Passed with no mentor, and a save of that shift refuses
# the row ("Pick a mentor before recording a result.") until one is picked.
class AllowArtPassWithoutMentor < ActiveRecord::Migration[8.1]
  def up
    change_column_null :person_mentor, :mentor_id, true
  end

  # Refuses while a mentor-less pass exists, naming the cause rather than
  # failing on the first row NOT NULL cannot hold.
  def down
    if select_value("SELECT 1 FROM person_mentor WHERE mentor_id IS NULL LIMIT 1")
      raise ActiveRecord::IrreversibleMigration,
            "person_mentor holds ART passes with no mentor; give them a mentor or delete them first"
    end

    change_column_null :person_mentor, :mentor_id, false
  end
end
