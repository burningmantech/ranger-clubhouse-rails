# frozen_string_literal: true

class ProspectiveApplication::SendEmailMailer < ProspectiveApplicationMailer
  def send_message(application:, email_subject:, email_message:)
    @prospective_application_id = application.id
    liquid_assigns.merge!(
      application: application_values(application),
      email_subject: email_subject,
      email_message: formatted_text(email_message)
    )

    mail(
      from: vc_from,
      to: application.email,
      subject: liquid_subject(email_subject)
    )
  end
end
