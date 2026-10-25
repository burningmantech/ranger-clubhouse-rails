# frozen_string_literal: true

class PhotoApprovedMailer < ApplicationMailer
  def notify(person:)
    liquid_assigns[:is_applicant] = person.is_applicant?

    mail(
      from: vc_from,
      to: person.email,
      subject: liquid_subject
    )
  end
end
