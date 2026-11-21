# frozen_string_literal: true

# Tells a training session's lead trainers that another trainer joined or left
# its trainer roster, and who is signed up now.
class TrainerRosterChangeMailer < ApplicationMailer
  # From the do-not-reply address, with replies going to the position's
  # contacts: SES sends only from an address it has verified.
  #
  # @param session_slot [Slot] the session the leads run
  # @param training [Position] the training whose pages show that session
  # @param change [String] "added" or "removed"
  # @param trainer [Hash] {callsign:, position_title:} of whoever joined or left
  # @param trainers [Array<Hash>] the roster now: {callsign:, position_title:, is_lead:, is_changed:}
  # @param lead_emails [Array<String>]
  # @param changed_by [String, nil] callsign, nil when the trainer did it themself
  # @param reason [String, nil] why a sweep removed them ("position revoked")
  def notify(session_slot:, training:, change:, trainer:, trainers:, lead_emails:, changed_by: nil, reason: nil)
    liquid_assigns.merge!(
      change:,
      trainer:,
      trainers:,
      trainer_count: trainers.size,
      changed_by:,
      reason:,
      session_url: training_session_url(Training.slug(training), session_slot.id),
      slot: {
        position_title: session_slot.position.title,
        description: session_slot.description,
        begins: session_slot.begins_human_format,
        date: ApplicationController.helpers.wday_month_day_format(session_slot.begins)
      }
    )

    mail(
      from: do_not_reply_from,
      reply_to: build_addresses(session_slot.position.contact_email).presence,
      to: lead_emails,
      subject: liquid_subject
    )
  end
end
