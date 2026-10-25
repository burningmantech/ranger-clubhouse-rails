# frozen_string_literal: true

class OnlineCourseEnrollmentMailer < ApplicationMailer
  def notify(person:, course_type:, password:)
    liquid_assigns[:person] = { callsign: person.callsign }

    mail(
      from: training_academy_from,
      to: person.email,
      subject: liquid_subject
    )
  end
end
