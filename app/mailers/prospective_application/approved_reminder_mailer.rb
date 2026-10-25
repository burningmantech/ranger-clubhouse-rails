# frozen_string_literal: true

class ProspectiveApplication::ApprovedReminderMailer < ApplicationMailer
  def notify(applications:)
    liquid_assigns[:applications] = applications.map do |application|
      {
        id: application.id,
        first_name: application.first_name,
        last_name: application.last_name,
        approved_handle: application.approved_handle
      }
    end

    mail(
      from: vc_from,
      to: EmailAddresses::VOLUNTEER_COORDINATORS_TEAM,
      subject: liquid_subject
    )
  end
end
