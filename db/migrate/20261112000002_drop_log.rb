# frozen_string_literal: true

# The Clubhouse 1 audit log (`log`, 2008 to 2019) leaves the application
# (owner's ruling, 2026-11-12): its page is gone, and the log is converted to
# legacy_log on the maintainer's machine, from a copy that still has the
# table. Run `bin/rails legacy_log:convert` there BEFORE this migration
# (`bin/rails db:migrate VERSION=20261112000001` stops one short of it); its
# rows cannot be brought back by a rollback, only the empty table.
class DropLog < ActiveRecord::Migration[8.1]
  def change
    drop_table :log, charset: "utf8mb3", collation: "utf8mb3_unicode_ci", comment: "logs certain actions" do |t|
      t.bigint :user_person_id, comment: "person_id of user making change", unsigned: true
      t.bigint :current_person_id, comment: "person_id of person affected by change (if any)", unsigned: true
      t.timestamp :occurred, default: -> { "current_timestamp()" }, null: false, comment: "time log entry created"
      t.string :event, limit: 500, null: false, comment: "summary of what was done"
      t.index :current_person_id, name: "current_person_id"
      t.index :occurred, name: "occurred"
      t.index :user_person_id, name: "user_person_id"
    end
  end
end
