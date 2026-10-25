# frozen_string_literal: true

class ProspectiveApplication::RrnCheckMailer < ProspectiveApplicationMailer
  def check(application:, status:, message_to_user: nil)
    @prospective_application_id = application.id
    liquid_assigns.merge!(
      application: application_values(application).merge(
        regional_callsign: application.regional_callsign.presence,
        regional_experience: application.regional_experience.presence &&
          formatted_text(application.regional_experience)
      ),
      status: status,
      message_to_user: message_to_user.presence && formatted_text(message_to_user)
    )

    mail(
      from: vc_from,
      to: build_addresses(Setting.get_value(Setting::RRN_EMAIL)),
      subject: liquid_subject
    )
  end
end
