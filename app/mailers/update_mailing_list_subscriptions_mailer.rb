# frozen_string_literal: true

class UpdateMailingListSubscriptionsMailer < ApplicationMailer
  def notify(person:, user:, old_email:, additional_lists:, teams:)
    liquid_assigns.merge!(
      old_email: old_email,
      additional_lists: additional_lists.presence && formatted_text(additional_lists),
      teams: teams.map(&:title),
      person: {
        callsign: person.callsign,
        email: person.email,
        url: person_url(person)
      }
    )

    mail(
      from: "rangers@burningman.org",
      to: build_addresses(Setting.get_value(Setting::MAILING_LIST_UPDATE_REQUEST_EMAIL)),
      subject: liquid_subject
    )
  end
end
