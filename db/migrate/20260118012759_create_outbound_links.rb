class CreateOutboundLinks < ActiveRecord::Migration[8.1]
  def change
    create_table :outbound_links do |t|
      t.string :url, null: false, limit: 1024
      t.string :url_type, null: false
      t.integer :person_id, null: true
      t.datetime :created_at, null: false

      t.index [:person_id, :created_at]
    end
  end
end
