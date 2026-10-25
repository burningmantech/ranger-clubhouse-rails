# frozen_string_literal: true

class PhotoRejectedMailer < ApplicationMailer
  def notify(person:, reject_reasons:, reject_message:)
    liquid_assigns.merge!(
      is_applicant: person.is_applicant?,
      reject_reasons: describe_reasons(reject_reasons),
      reject_message: reject_message.presence && formatted_text(reject_message)
    )

    mail(
      from: vc_from,
      to: person.email,
      subject: liquid_subject
    )
  end

  private

  # What each marked reason means. A reason no one recognises is passed along
  # as it was marked, so the message can say so rather than saying nothing.
  def describe_reasons(reasons)
    Array(reasons).map do |reason|
      known = PersonPhoto::REJECTIONS[reason]
      { code: reason, known: known.present?, message: known&.dig("message") }
    end
  end
end
