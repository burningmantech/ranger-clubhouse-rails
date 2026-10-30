# frozen_string_literal: true

# What SES reports back about the mail the Clubhouse sends: which messages
# reached the recipient, which bounced, and which the recipient marked as spam.
# AWS Simple Notification Service posts each report here.
#
# See https://docs.aws.amazon.com/ses/latest/dg/notification-contents.html
class Infrastructure::AwsSnsController < ApplicationController
  # No authentication -- this endpoint is called by AWS. The signature on the
  # message takes the place of a sign-in: see SnsMessage.
  skip_forgery_protection
  allow_unauthenticated_access
  skip_before_action :set_current_user
  skip_before_action :build_menu_items

  # A bounce to any of these is somebody else's mail system talking to itself,
  # not a Ranger with a bad address.
  IGNORED_DOMAINS = %w[burningman.slack.com].freeze

  def notification
    sns = SnsMessage.parse(request.raw_post)

    return head :bad_request unless sns
    return head :forbidden unless authentic?(sns)

    # A new subscription is live only once the URL in it has been fetched.
    if sns.subscription_confirmation?
      confirm_subscription(sns)
      return head :ok
    end

    case sns.event_type
    when "Delivery" then record_deliveries(sns)
    when "Bounce" then record_bounces(sns)
    when "Complaint" then record_complaints(sns)
    when nil then ErrorLog.record("sns-unknown-format", data: { body: sns.envelope })
    else ErrorLog.record("sns-message-unknown-type", data: { message: sns.payload })
    end

    # Always 200, even for a shape this does not understand. Anything else and
    # SNS redelivers the same message for hours.
    head :ok
  end

  private

  # Signed by SNS, and published by our own topic. The signature alone only
  # proves some AWS account sent it -- any of them can create a topic and
  # report whatever bounces it likes about our Rangers.
  def authentic?(sns)
    topic = Setting.get_value(Setting::SES_SNS_TOPIC_ARN).to_s

    if topic.blank?
      ErrorLog.record("sns-topic-not-configured", data: { topic_arn: sns.topic_arn })
      return false
    end

    unless sns.topic_arn == topic
      ErrorLog.record("sns-wrong-topic", data: { topic_arn: sns.topic_arn })
      return false
    end

    return true if sns.verified?

    ErrorLog.record("sns-signature-invalid", data: { message_id: sns.envelope["MessageId"] })
    false
  end

  def confirm_subscription(sns)
    return if SnsMessage.fetch_aws(sns.subscribe_url)

    ErrorLog.record("sns-subscription-ping-failed", data: { subscribe_url: sns.subscribe_url })
  rescue StandardError => e
    ErrorLog.record_exception(e, "sns-subscription-ping-exception", extra: { message: sns.envelope })
  end

  # Delivery reports arrive for every message that lands, so they are only
  # stamped on the mail log -- an action log entry apiece would bury every
  # other thing the Clubhouse records.
  def record_deliveries(sns)
    message_id = sns.message_id
    return if message_id.blank?

    Array(sns.payload.dig("delivery", "recipients")).each do |email|
      MailLog.mark_as_delivered(email, message_id)
    end
  end

  def record_bounces(sns)
    bounce_type = sns.payload.dig("bounce", "bounceType")
    sub_type = sns.payload.dig("bounce", "bounceSubType")
    message_id = sns.message_id

    each_recipient(sns, "bounce", "bouncedRecipients") do |email|
      mail_log = MailLog.mark_as_bounced(email, message_id) if message_id.present?
      # Whatever its type, a bounce means this copy did not arrive, so a
      # broadcast email's row says bounced.
      BroadcastMessage.mark_email_bounced(mail_log)
      # Every sub-type, SES's own suppression list included, says the address
      # takes no mail, so it is recorded under the address the Clubhouse sent to.
      if bounce_type == "Permanent"
        EmailSuppression.record(sns.sent_address(email), reason: EmailSuppression::BOUNCE, sub_type:, message_id:)
      end
      person = Person.find_by(email: email)

      ActionLog.record(nil, "email-bouncing", "", {
        to_email: email,
        message_id: message_id,
        bounce_type: bounce_type,
        mail_log_id: mail_log&.id,
        message: sns.payload
      }, person&.id)
    end
  end

  def record_complaints(sns)
    sub_type = sns.payload.dig("complaint", "complaintSubType")
    message_id = sns.message_id

    each_recipient(sns, "complaint", "complainedRecipients") do |email|
      mail_log = MailLog.mark_as_complaint(email, message_id) if message_id.present?
      EmailSuppression.record(sns.sent_address(email), reason: EmailSuppression::COMPLAINT, sub_type:, message_id:)
      person = Person.find_by(email: email)

      ActionLog.record(nil, "email-complaint", "", {
        to_email: email,
        message_id: message_id,
        mail_log_id: mail_log&.id,
        message: sns.payload
      }, person&.id)
    end
  end

  # Walk the addresses a bounce or complaint names, skipping the ones nothing
  # can be done about. An address missing altogether is a malformed report and
  # worth a note -- the report says something went wrong but not to whom.
  def each_recipient(sns, section, key)
    Array(sns.payload.dig(section, key)).each do |recipient|
      email = recipient.is_a?(Hash) ? recipient["emailAddress"].to_s : recipient.to_s

      if email.blank?
        ErrorLog.record("sns-malformed-notification",
                        data: { reason: "emailAddress field is missing", sns: sns.payload })
        next
      end

      next if IGNORED_DOMAINS.any? { |domain| email.downcase.include?(domain) }

      yield email
    end
  end
end
