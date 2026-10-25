# frozen_string_literal: true

# One row per address that bounced for good or reported Clubhouse email as
# spam, written from SES's reports: see EmailSuppression. Rows never expire,
# and stay when their person changes address.
class CreateEmailSuppression < ActiveRecord::Migration[8.1]
  def change
    create_table :email_suppression,
                 comment: "addresses that bounced for good or reported Clubhouse email as spam" do |t|
      # Stored as normalized by EmailSuppression (stripped, lowercase).
      t.string :email, limit: 255, null: false
      t.column :reason, "enum('bounce','complaint')", null: false
      t.string :sub_type, comment: "the latest report's bounceSubType or complaintSubType"
      t.datetime :first_reported_at, null: false
      t.datetime :last_reported_at, null: false
      t.integer :report_count, null: false, default: 1
      t.string :message_id, comment: "the id SES gave the email the latest report was about"
      t.timestamps

      t.index :email, unique: true
    end
  end
end
