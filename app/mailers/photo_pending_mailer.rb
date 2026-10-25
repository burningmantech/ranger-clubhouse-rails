# frozen_string_literal: true

class PhotoPendingMailer < ApplicationMailer
  def notify(pending_photos:)
    liquid_assigns.merge!(
      count: pending_photos.size,
      review_url: vc_photos_review_url,
      photos: pending_photos.map do |photo|
        {
          callsign: photo.person.callsign,
          status: photo.person.status,
          uploaded_ago: ActionController::Base.helpers.time_ago_in_words(photo.created_at)
        }
      end
    )

    mail(
      from: vc_from,
      to: build_addresses(EmailAddresses::VOLUNTEER_COORDINATORS_TEAM),
      subject: liquid_subject
    )
  end
end
