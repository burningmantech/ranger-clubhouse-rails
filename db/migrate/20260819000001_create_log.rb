# The audit log written by the very first version of the Clubhouse. It holds
# 2.4 million rows spanning July 2008 to October 2019 and nothing has added to
# it since; it is kept for historical and investigative reading only.
#
# The table has always existed in the shared database but was never described
# here, so a freshly loaded schema -- the test database among them -- had no
# such table and nothing that reads it could be tested.
#
# `up` and `down` rather than `change`: the automatic inverse of create_table
# is drop_table, and it drops the `:if_not_exists` along the way. A rollback
# would take the shared table and every row in it, none of which this
# migration created and none of which it could put back.
class CreateLog < ActiveRecord::Migration[8.1]
  def up
    create_table :log, charset: "utf8mb3", collation: "utf8mb3_unicode_ci",
                       comment: "logs certain actions", if_not_exists: true do |t|
      t.bigint :user_person_id, unsigned: true, comment: "person_id of user making change"
      t.bigint :current_person_id, unsigned: true,
               comment: "person_id of person affected by change (if any)"
      t.timestamp :occurred, null: false, default: -> { "current_timestamp()" },
                  comment: "time log entry created"
      t.string :event, limit: 500, null: false, comment: "summary of what was done"

      t.index :current_person_id, name: "current_person_id"
      t.index :user_person_id, name: "user_person_id"
      t.index :occurred, name: "occurred"
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
          "The log table is shared legacy data. Dropping it would destroy 2.4 million rows this migration did not create."
  end
end
