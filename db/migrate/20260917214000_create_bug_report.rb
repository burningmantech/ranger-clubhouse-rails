# Problems people report from the Bug Report button in the top menu.
#
# Rows are written once and never edited, so there is no updated_at. The log
# page reads the newest rows by id, which needs no index of its own.
class CreateBugReport < ActiveRecord::Migration[8.1]
  def change
    create_table :bug_report do |t|
      t.bigint :person_id, null: false
      t.text :description, null: false
      # The page the person was on. Path only -- see BugReportsController.
      t.string :url
      # 45 characters is the longest an IPv6 address gets when written out.
      t.string :ip, limit: 45
      t.string :user_agent
      t.datetime :created_at, null: false

      t.index :person_id
    end
  end
end
