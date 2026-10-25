# frozen_string_literal: true

class OnlineCourseCompletedMailer < ApplicationMailer
  def notify(person:)
    liquid_assigns.merge!(
      person: { callsign: person.callsign, first_name: person.first_name },
      is_pnv: person.pnv?,
      is_auditor: person.is_auditor?
    )

    mail(
      from: training_academy_from,
      to: person.email,
      subject: liquid_subject
    )
  end
end
