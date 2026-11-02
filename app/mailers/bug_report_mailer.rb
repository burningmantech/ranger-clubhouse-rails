# frozen_string_literal: true

class BugReportMailer < ApplicationMailer
  # Bug reports are for Tech Ninjas only, so the mail log keeps no copy of what
  # was reported.
  self.withhold_body_from_mail_log = true
  self.subject_values = %i[person]

  # The report's values come with the job rather than the record, so a purge or
  # a deleted account before the job runs cannot stop the email.
  def notify(callsign:, email:, browser:, page:, description:)
    liquid_assigns.merge!(
      person: { callsign:, email: },
      browser:,
      page:,
      # Escaped first, so what someone typed shows as text, never as markup, as
      # it does on the log page.
      description: formatted_text(ERB::Util.html_escape(description)),
      log_url: admin_bug_reports_url
    )

    mail(
      from: do_not_reply_from,
      to: EmailAddresses::TECH_CADRE,
      # So a reply reaches the reporter. An address the mail library cannot take
      # is left off, or the email would never go.
      reply_to: (email if EmailAddresses.sendable?(email)),
      subject: liquid_subject
    )
  end
end
