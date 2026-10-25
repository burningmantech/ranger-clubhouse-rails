# frozen_string_literal: true

class ProspectiveApplication::WhyRangerQuestionMailer < ProspectiveApplicationMailer
  def notify(application:, status:, message_to_user: nil)
    build_mail(application:, status:, message_to_user:)
  end
end
