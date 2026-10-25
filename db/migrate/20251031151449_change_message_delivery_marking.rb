class ChangeMessageDeliveryMarking < ActiveRecord::Migration[8.0]
  def up
    add_column :person_message, :sender_read, :boolean, null: false, default: true
    add_column :person_message, :recipient_read, :boolean, null: false, default: false
    add_column :person_message, :sender_archived, :boolean, null: false, default: false
    add_column :person_message, :recipient_archived, :boolean, null: false, default: false
  end

  def down
    remove_column :person_message, :sender_read
    remove_column :person_message, :recipient_read
    remove_column :person_message, :sender_archived
    remove_column :person_message, :recipient_archived
  end
end
