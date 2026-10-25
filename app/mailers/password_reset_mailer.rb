# frozen_string_literal: true

class PasswordResetMailer < ApplicationMailer
  # The reset link signs its holder in, so the mail log keeps no copy of it.
  self.withhold_body_from_mail_log = true

  def notify(person:, reset_token:)
    liquid_assigns.merge!(
      greeting: "Hi #{person.desired_first_name}",
      support_email: EmailAddresses::TECH_CADRE,
      reset_url: reset_token_url(token: reset_token)
    )

    mail(
      from: do_not_reply_from,
      to: person.email,
      subject: liquid_subject("Ranger Clubhouse Password Reset")
    )
  end
end
