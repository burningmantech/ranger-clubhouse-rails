# frozen_string_literal: true

class ProspectiveApplication::PiiIssueMailer < ProspectiveApplicationMailer
  def notify(application:, status:, message_to_user: nil)
    build_mail(application:, status:, message_to_user:,
               application_extra: { blank_fields: application.blank_personal_info })
  end
end
