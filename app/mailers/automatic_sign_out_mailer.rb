# frozen_string_literal: true

class AutomaticSignOutMailer < ApplicationMailer
  def notify(contact_email:, title:, hour_cap:, entries:)
    liquid_assigns.merge!(
      title: title,
      hour_cap: hour_cap,
      entries: entries.map do |entry|
        {
          callsign: entry.person.callsign,
          person_url: person_url(entry.person),
          position_title: entry.position.title,
          on_duty: entry.on_duty.to_s,
          off_duty: entry.off_duty.to_s
        }
      end
    )

    mail(
      from: do_not_reply_from,
      to: build_addresses(contact_email),
      subject: liquid_subject
    )
  end
end
