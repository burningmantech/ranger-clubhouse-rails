# frozen_string_literal: true

class ExpiredHandleReservationsMailer < ApplicationMailer
  def notify(handles:)
    liquid_assigns[:handles] = handles

    mail(
      from: vc_from,
      to: EmailAddresses::VOLUNTEER_COORDINATORS_TEAM,
      subject: liquid_subject
    )
  end
end
