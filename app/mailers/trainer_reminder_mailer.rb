# frozen_string_literal: true

class TrainerReminderMailer < ApplicationMailer
  # From the do-not-reply address, with replies going to the position's
  # contacts: SES sends only from an address it has verified, and a contact
  # address can be anyone's.
  def notify(slot:, trainer_emails:)
    liquid_assigns[:slot] = {
      position_title: slot.position.title,
      description: slot.description,
      begins: slot.begins_human_format
    }

    contacts = build_addresses(slot.position.contact_email)

    mail(
      from: do_not_reply_from,
      reply_to: contacts,
      to: contacts + Array(trainer_emails),
      subject: liquid_subject
    )
  end
end
