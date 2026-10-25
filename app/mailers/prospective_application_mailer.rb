# frozen_string_literal: true

class ProspectiveApplicationMailer < ApplicationMailer
  # Base class for prospective application mailers. A child class fills in
  # anything its own template needs, then calls build_mail.

  protected

  # Build the email with standard prospective application settings
  #
  # @param application [ProspectiveApplication] the application
  # @param status [String] the application status
  # @param message_to_user [String, nil] optional message to include
  # @param application_extra [Hash] more about the application, for templates that ask for it
  def build_mail(application:, status:, message_to_user: nil, application_extra: {})
    @prospective_application_id = application.id
    liquid_assigns.merge!(
      application: application_values(application).merge(application_extra),
      status: status,
      message_to_user: message_to_user.presence && formatted_text(message_to_user)
    )

    mail(
      from: vc_from,
      to: envelope_to(application),
      subject: liquid_subject
    )
  end

  # What every message about an application can show, including the footer that
  # names the application and whoever is looking after it.
  def application_values(application)
    assigned = application.assigned_person

    {
      id: application.id,
      first_name: application.first_name,
      last_name: application.last_name,
      approved_handle: application.approved_handle,
      assigned_to: assigned && { id: assigned.id, callsign: assigned.callsign }
    }
  end

  private

  # Determine the recipient - use sandbox if configured, otherwise the applicant
  def envelope_to(application)
    sandbox = Setting.get_value(Setting::PROSPECTIVE_APPLICATION_MAIL_SANDBOX)
    if sandbox.present?
      build_addresses(sandbox)
    else
      application.email
    end
  end
end
