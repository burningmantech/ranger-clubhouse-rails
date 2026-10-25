# frozen_string_literal: true

class AlertWhenSignUpsEmptyMailer < ApplicationMailer
  def notify(position:, slot:, trainee_signups:, person: nil)
    liquid_assigns.merge!(
      trainee_signups: trainee_signups.presence,
      dropped_by: person&.callsign,
      slot: {
        position_title: position.title,
        description: slot.description,
        begins: slot.begins_human_format
      }
    )

    mail(
      from: do_not_reply_from,
      to: build_addresses(position.contact_email),
      subject: liquid_subject
    )
  end
end
