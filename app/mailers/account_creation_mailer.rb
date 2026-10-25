# frozen_string_literal: true

class AccountCreationMailer < ApplicationMailer
  def notify(status:, details:, person:, intent:)
    liquid_assigns.merge!(
      status: status,
      details: details,
      intent: intent,
      person: {
        callsign: person.callsign,
        first_name: person.first_name,
        last_name: person.last_name,
        email: person.email
      }
    )

    mail(
      from: from_do_not_reply,
      to: build_addresses(Setting.get_value(Setting::ACCOUNT_CREATION_EMAIL)),
      subject: liquid_subject("[Clubhouse] Account creation #{person.callsign}")
    )
  end
end
