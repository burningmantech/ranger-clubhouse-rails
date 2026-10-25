# frozen_string_literal: true

class AutomaticActiveConversionMailer < ApplicationMailer
  def notify(person:, old_status:, position_title:, worker_callsign:)
    liquid_assigns.merge!(
      person: { callsign: person.callsign },
      old_status: old_status,
      position_title: position_title,
      worker_callsign: worker_callsign,
      converted_at: Time.current.strftime("%A %b %d @ %H:%M")
    )

    mail(
      from: vc_from,
      to: build_addresses(EmailAddresses::VOLUNTEER_COORDINATORS_TEAM),
      subject: liquid_subject("[Clubhouse] #{person.callsign} automatic conversion to active")
    )
  end
end
