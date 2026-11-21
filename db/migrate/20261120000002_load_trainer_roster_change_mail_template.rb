# frozen_string_literal: true

# Loads the wording of the email a session's lead trainers get when a trainer
# joins or leaves. A template reaches a database only by being loaded, and no
# deploy step runs `rails mail_templates:load`, so without this the email would
# fail. Loading again is safe: wording edited in the Clubhouse is left as it is.
class LoadTrainerRosterChangeMailTemplate < ActiveRecord::Migration[8.1]
  def up
    MailTemplateSeeds.load!
  end

  def down
    MailTemplate.where(tag: "trainer_roster_change_mailer/notify").delete_all
  end
end
