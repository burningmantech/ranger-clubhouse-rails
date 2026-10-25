# frozen_string_literal: true

class RbsMailer < ApplicationMailer
  # One broadcast email. The alert type is named in the footer so the reader
  # knows which preference turns messages like this one off. Drawn without a
  # recipient: it is handed to SES, which writes each person's To line.
  #
  # A short broadcast's subject is its text message, typed in a box that takes
  # line breaks; a mail header cannot hold one.
  def broadcast(subject:, rbs_message:, alert:, expires_at:)
    expires = expires_at.presence && Time.zone.parse(expires_at.to_s)

    liquid_assigns.merge!(
      broadcast_subject: subject,
      broadcast_message: formatted_text(rbs_message),
      expires_at: expires&.strftime("%A, %B %d, %Y %H:%M:%S"),
      alert: {
        title: alert.title,
        period: alert.on_playa ? "On Playa" : "Pre-Event"
      }
    )

    mail(
      from: do_not_reply_from,
      subject: liquid_subject(subject).to_s.squish
    )
  end
end
