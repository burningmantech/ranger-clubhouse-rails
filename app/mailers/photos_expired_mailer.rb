# frozen_string_literal: true

class PhotosExpiredMailer < ApplicationMailer
  def notify(expired_photos:)
    liquid_assigns[:photos] = expired_photos.map do |photo|
      {
        person_id: photo[:person_id],
        callsign: photo[:callsign],
        person_photo_id: photo[:person_photo_id],
        created_at: photo[:created_at].to_s
      }
    end

    mail(
      from: vc_from,
      to: build_addresses(Setting.get_value(Setting::PHOTOS_EXPIRED_EMAIL)),
      subject: liquid_subject
    )
  end
end
