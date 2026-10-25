# frozen_string_literal: true

class ProspectiveApplication::RejectUnqualifiedMailer < ProspectiveApplicationMailer
  def notify(application:, status:, message_to_user: nil)
    build_mail(
      application:, status:, message_to_user:,
      application_extra: {
        experience_none: application.experience_none?,
        qualified_events_count: application.qualified_events.size,
        old_events: application.old_events,
        have_pandemic_years: application.have_pandemic_years?
      }
    )
  end
end
