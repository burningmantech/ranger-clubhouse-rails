class CreatePersonFavorite < ActiveRecord::Migration[8.1]
  def change
    create_table :person_favorite do |t|
      t.bigint :person_id, null: false
      t.string :path, null: false, limit: 191
      t.datetime :created_at, null: false

      t.index [:person_id, :path], unique: true
    end
  end
end
