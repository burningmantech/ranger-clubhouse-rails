# frozen_string_literal: true

class ContactMailer < ApplicationMailer
  # The email carries what one person wrote to another, so the mail log keeps
  # no copy of it.
  self.withhold_body_from_mail_log = true

  def send_message(sender_person:, person:, message_subject:, contact_message:)
    liquid_assigns.merge!(
      person: { callsign: person.callsign },
      sender_callsign: sender_person.callsign,
      message_subject: message_subject,
      contact_message: formatted_text(contact_message)
    )

    mail(
      from: format_from(from_do_not_reply, "The Black Rock Rangers"),
      to: person.email,
      subject: liquid_subject(message_subject)
    )
  end
end
