# frozen_string_literal: true

class TrainingSessionFullMailer < ApplicationMailer
  # From the do-not-reply address, with replies going to the position's
  # contacts: SES sends only from an address it has verified, and a contact
  # address can be anyone's.
  def notify(slot:, signed_up:, notify_email:)
    liquid_assigns.merge!(
      signed_up: signed_up,
      slot: {
        position_title: slot.position.title,
        description: slot.description,
        begins: slot.begins_human_format,
        max: slot.max
      }
    )

    emails = build_addresses(notify_email)

    mail(
      from: do_not_reply_from,
      reply_to: emails,
      to: emails,
      subject: liquid_subject
    )
  end
end
