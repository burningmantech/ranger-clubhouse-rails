# frozen_string_literal: true

class OnlineCourseResetPasswordMailer < ApplicationMailer
  # The email carries an online course password, so the mail log keeps no
  # copy of it.
  self.withhold_body_from_mail_log = true

  def notify(person:, password:)
    liquid_assigns.merge!(
      person: { callsign: person.callsign, lms_username: person.lms_username },
      password: password,
      course_url: Setting.get_value(Setting::ONLINE_COURSE_SITE_URL)
    )

    mail(
      from: training_academy_from,
      to: person.email,
      subject: liquid_subject
    )
  end
end
