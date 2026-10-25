# frozen_string_literal: true

class NotifyVcEmailChangeMailer < ApplicationMailer
  def notify(person:, old_email:)
    liquid_assigns.merge!(
      old_email: old_email,
      person: {
        callsign: person.callsign,
        first_name: person.first_name,
        last_name: person.last_name,
        email: person.email
      }
    )

    mail(
      from: vc_from,
      to: EmailAddresses::VOLUNTEER_COORDINATORS_TEAM,
      subject: liquid_subject
    )
  end
end
