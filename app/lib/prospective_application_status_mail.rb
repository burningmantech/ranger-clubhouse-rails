# frozen_string_literal: true

# Dispatches the applicant email associated with a prospective application
# status change, and records it in the application's audit trail. Its mail
# log rows are written as it is delivered (ApplicationMailer#record_mail_log).
class ProspectiveApplicationStatusMail
  STATUS_TO_MAILER = {
    ProspectiveApplication::STATUS_APPROVED => ProspectiveApplication::ApprovedCallsignMailer,
    ProspectiveApplication::STATUS_HOLD_AGE_ISSUE => ProspectiveApplication::AgeConfirmationMailer,
    ProspectiveApplication::STATUS_HOLD_PII_ISSUE => ProspectiveApplication::PiiIssueMailer,
    ProspectiveApplication::STATUS_HOLD_QUALIFICATION_ISSUE => ProspectiveApplication::ExperienceConfirmationMailer,
    ProspectiveApplication::STATUS_HOLD_RRN_CHECK => ProspectiveApplication::RrnCheckMailer,
    ProspectiveApplication::STATUS_HOLD_WHY_RANGER_QUESTION => ProspectiveApplication::WhyRangerQuestionMailer,
    ProspectiveApplication::STATUS_MORE_HANDLES => ProspectiveApplication::MoreHandlesMailer,
    ProspectiveApplication::STATUS_REJECT_REGIONAL => ProspectiveApplication::RejectRegionalMailer,
    ProspectiveApplication::STATUS_REJECT_RETURNING_RANGER => ProspectiveApplication::ReturningRangerMailer,
    ProspectiveApplication::STATUS_REJECT_TOO_YOUNG => ProspectiveApplication::RejectTooYoungMailer,
    ProspectiveApplication::STATUS_REJECT_UNQUALIFIED => ProspectiveApplication::RejectUnqualifiedMailer
  }.freeze

  class << self
    # Send the email for the given status. Statuses with no associated
    # email are a silent no-op.
    def execute(application, status, message = nil)
      delivery = build(application, status, message)
      return unless delivery

      deliver_and_log(application, delivery)
    end

    # Deliver any prospective-application email and record it in the
    # application's audit trail. The mailer writes its mail log rows, under
    # the application, as the email goes.
    def deliver_and_log(application, delivery)
      message = delivery.deliver_now
      ProspectiveApplicationLog.record(application.id, ProspectiveApplicationLog::ACTION_EMAILED,
                                       { "subject" => message.subject })
    end

    # Render the email for the given status without sending it.
    def preview(application, status, message = nil)
      delivery = build(application, status, message)
      raise ArgumentError, "Status has no associated email: #{status}" unless delivery

      html_body(delivery.message)
    end

    private

    def build(application, status, message)
      mailer = STATUS_TO_MAILER[status]
      return nil unless mailer

      if mailer == ProspectiveApplication::RrnCheckMailer
        mailer.check(application:, status:, message_to_user: message)
      else
        mailer.notify(application:, status:, message_to_user: message)
      end
    end

    def html_body(message)
      MailLog.html_body(message)
    end
  end
end
