class CreateSessions < ActiveRecord::Migration[8.0]
  def change
    create_table :sessions do |t|
      t.string :session_id
      t.string :ip_address
      t.string :user_agent
      t.integer :person_id
      t.text :data, size: :medium

      t.timestamps

      t.index :session_id, unique: true
      t.index :person_id
    end
  end
end
