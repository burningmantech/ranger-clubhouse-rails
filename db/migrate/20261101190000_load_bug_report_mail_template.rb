# frozen_string_literal: true

# Loads the wording of the email the Tech Cadre gets for each bug report. A
# template reaches a database only by being loaded (see CreateMailTemplate), and
# no deploy step runs `rails mail_templates:load`, so without this every bug
# report's email would fail. Loading again is safe: wording edited in the
# Clubhouse is left as it is.
class LoadBugReportMailTemplate < ActiveRecord::Migration[8.1]
  def up
    MailTemplateSeeds.load!
  end

  def down
    MailTemplate.where(tag: "bug_report_mailer/notify").delete_all
  end
end
