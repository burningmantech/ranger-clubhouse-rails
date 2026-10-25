# frozen_string_literal: true

class WelcomeMailer < ApplicationMailer
  # The invite link signs its holder in, so the mail log keeps no copy of it.
  self.withhold_body_from_mail_log = true

  def notify(person:, invite_token:)
    liquid_assigns[:invite_url] = reset_token_url(token: invite_token, welcome: 1)

    mail(
      from: vc_from,
      to: person.email,
      subject: liquid_subject
    )
  end
end
