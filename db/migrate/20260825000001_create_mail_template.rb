# The wording of the messages the Clubhouse sends. One row per message, holding
# its subject and its body, so the text can be changed without a code change.
#
# The templates that ship with the Clubhouse are loaded from db/mail_templates by
# `rails mail_templates:load`, which is why this migration seeds nothing itself:
# a message added later would need a migration of its own.
class CreateMailTemplate < ActiveRecord::Migration[8.1]
  def up
    create_table :mail_template, comment: "wording of the messages the Clubhouse sends" do |t|
      t.string :tag, limit: 191, null: false,
               comment: "which message this is the wording for, e.g. welcome_mailer/notify"
      t.string :description, limit: 191, null: false, comment: "what the message is for"
      t.string :subject, limit: 500, comment: "subject line; empty for a shared piece"
      t.text :body, size: :long, null: false, comment: "the HTML part"
      t.text :text_body, size: :long, comment: "the plain text part, where the message has one"
      t.string :seeded_digest, limit: 64,
               comment: "fingerprint of the text last loaded from db/mail_templates"
      t.bigint :person_create_id, unsigned: true
      t.bigint :person_update_id, unsigned: true
      t.timestamps

      t.index :tag, unique: true
    end
  end

  def down
    drop_table :mail_template
  end
end
