class AdjustPersonPhoto < ActiveRecord::Migration[8.0]
  def up
    change_table :person_photo do |t|
      t.json :reject_reasons_json, default: {}
      t.json :cropping, null: false, default: {}
    end

    execute <<-SQL
    UPDATE person_photo SET reject_reasons_json = reject_reasons
    SQL
    remove_column :person_photo, :reject_reasons

    change_table :person_photo do |t|
      t.rename :reject_reasons_json, :reject_reasons
    end

    execute <<-SQL
ALTER TABLE person_photo MODIFY COLUMN status enum(#{PersonPhoto::STATUSES.map { |s| %Q("#{s}") }.join(",")}) NOT NULL;
    SQL

    #  Rake::Task['photos:convert_to_active_storage'].invoke
  end

  def down
  end
end
