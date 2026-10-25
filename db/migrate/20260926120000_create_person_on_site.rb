# frozen_string_literal: true

# One row each time a person is marked on site or off site, and who did it.
# Rows are written once and never edited, so there is no updated_at.
class CreatePersonOnSite < ActiveRecord::Migration[8.1]
  def change
    create_table :person_on_site do |t|
      t.bigint :person_id, null: false
      # Empty when no one was signed in (rake, console, a job).
      t.bigint :creator_person_id
      t.column :action, "enum('on-site','off-site')", null: false
      t.datetime :created_at, null: false

      # The site-log page reads one person's rows by date.
      t.index [:person_id, :created_at]
      t.index :creator_person_id
    end
  end
end
