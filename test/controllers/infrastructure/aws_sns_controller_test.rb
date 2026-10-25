# frozen_string_literal: true

require "test_helper"

class Infrastructure::AwsSnsControllerTest < ActionDispatch::IntegrationTest
  include ActiveSupport::Testing::TimeHelpers
  include EmailSuppressionTestHelper
  include RbsTestHelper

  TOPIC = "arn:aws:sns:us-west-2:123456789012:clubhouse-ses"
  # An id the way SES writes them.
  SES_ID = "0100018f2b6c1a2e-1c7d9a3f-6b2e-4f0a-9a1b-2c3d4e5f6a7b-000000"
  CERT_URL = "https://sns.us-west-2.amazonaws.com/SimpleNotificationService-abc123.pem"

  # One key pair for the whole file. Generating RSA keys is slow enough that
  # doing it per test is noticeable.
  KEY = OpenSSL::PKey::RSA.new(2048)
  CERTIFICATE = begin
    name = OpenSSL::X509::Name.parse("/CN=sns.amazonaws.com")
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2
    cert.serial = 1
    cert.subject = name
    cert.issuer = name
    cert.public_key = KEY.public_key
    cert.not_before = Time.now - 60
    cert.not_after = Time.now + 3600
    cert.sign(KEY, OpenSSL::Digest::SHA256.new)
    cert.to_pem
  end

  setup do
    Setting.create!(name: Setting::SES_SNS_TOPIC_ARN, value: TOPIC)

    @person = person(:active_ranger)
    @person.update_columns(email: "ranger@example.com", is_bouncing: false)

    @mail_log = MailLog.create!(
      message_id: "message-1@example.com",
      from_email: "do-not-reply@burningman.org",
      to_email: "ranger@example.com",
      subject: "Shift reminder",
      was_sent: true
    )

    # A Ranger a broadcast reached, and the broadcast.
    @listener = rbs_person("Listener")
    @broadcast = rbs_broadcast(sender: @person)

    @fetched = []
    stub_fetch_aws
  end

  teardown do
    restore_fetch_aws
    travel_back
  end

  # =========================================================================
  # Delivery
  # =========================================================================

  test "a delivery report stamps the mail log" do
    post_event({ "notificationType" => "Delivery",
               "mail" => { "messageId" => "message-1@example.com" },
               "delivery" => { "recipients" => ["ranger@example.com"] } })

    assert_response :success
    assert_not_nil @mail_log.reload.delivered_at
  end

  test "a delivery report writes no action log" do
    assert_no_difference -> { ActionLog.count } do
      post_event({ "notificationType" => "Delivery",
                 "mail" => { "messageId" => "message-1@example.com" },
                 "delivery" => { "recipients" => ["ranger@example.com"] } })
    end
  end

  # A broadcast email sent to the test address is recorded under the id SES
  # gave it and the address it really went to, which is what SES reports back.
  test "a delivery report for an email sent to the test address stamps that email's row" do
    sent = test_address_log

    post_event({ "notificationType" => "Delivery",
               "mail" => { "messageId" => SES_ID },
               "delivery" => { "recipients" => ["test+#{@person.id}@example.com"] } })

    assert_not_nil sent.reload.delivered_at
    assert_nil @mail_log.reload.delivered_at
  end

  test "a delivery report for an address the row was not sent to changes nothing" do
    sent = test_address_log

    post_event({ "notificationType" => "Delivery",
               "mail" => { "messageId" => SES_ID },
               "delivery" => { "recipients" => ["ranger@example.com"] } })

    assert_response :success
    assert_nil sent.reload.delivered_at
  end

  # =========================================================================
  # Bounce
  # =========================================================================

  test "a permanent bounce marks the mail log, the person, and the action log" do
    post_event(bounce_event("Permanent"))

    assert_response :success
    assert @mail_log.reload.did_bounce
    assert @person.reload.is_bouncing
    assert_equal 1, ActionLog.where(event: "email-bouncing", target_person_id: @person.id).count
  end

  test "a transient bounce leaves the person sendable" do
    post_event(bounce_event("Transient"))

    assert @mail_log.reload.did_bounce
    assert_not @person.reload.is_bouncing
  end

  # Mail sent through the :ses_mail delivery method is logged once per To
  # address, each row under the id SES gave the email, so a bounce for one
  # recipient finds that recipient's row alone.
  test "a bounce for one address of a two-address email marks only that address's row" do
    message = Mail.new(from: "do-not-reply@burningman.org", to: ["ranger@example.com", "lead@example.com"],
                       subject: "Application update", body: "Hello")
    message.header[:ses_message_id] = SES_ID
    ranger_row, lead_row = MailLog.record_delivery(message, sender_id: @person.id)

    post_event({ "notificationType" => "Bounce",
               "mail" => { "messageId" => SES_ID },
               "bounce" => {
                 "bounceType" => "Transient",
                 "bouncedRecipients" => [{ "emailAddress" => "lead@example.com" }]
               } })

    assert_response :success
    assert lead_row.reload.did_bounce
    assert_not ranger_row.reload.did_bounce
    assert_not @mail_log.reload.did_bounce
    assert_equal lead_row.id, ActionLog.find_by!(event: "email-bouncing").data["mail_log_id"]
  end

  test "a slack bounce is ignored" do
    post_event({ "notificationType" => "Bounce",
               "mail" => { "messageId" => "message-1@example.com" },
               "bounce" => {
                 "bounceType" => "Permanent",
                 "bouncedRecipients" => [{ "emailAddress" => "nobody@burningman.slack.com" }]
               } })

    assert_response :success
    assert_equal 0, ActionLog.where(event: "email-bouncing").count
  end

  test "a bounce naming no address is logged as malformed" do
    post_event({ "notificationType" => "Bounce",
               "mail" => { "messageId" => "message-1@example.com" },
               "bounce" => { "bounceType" => "Permanent", "bouncedRecipients" => [{}] } })

    assert_equal 1, ErrorLog.where(error_type: "sns-malformed-notification").count
  end

  # =========================================================================
  # The address's record of bounces and spam reports
  # =========================================================================

  # Every Permanent sub-type marks the address, SES's own list included.
  ["General", EmailSuppression::ON_ACCOUNT_SUPPRESSION_LIST, nil].each do |sub_type|
    test "a permanent bounce with #{sub_type || "no"} sub-type records the address" do
      travel_to Time.zone.local(2026, 10, 9, 14, 30, 0)

      post_event(bounce_event("Permanent", sub_type:, message_id: SES_ID))

      row = EmailSuppression.find_by!(email: "ranger@example.com")
      assert_equal EmailSuppression::BOUNCE, row.reason
      sub_type ? assert_equal(sub_type, row.sub_type) : assert_nil(row.sub_type)
      assert_equal Time.zone.local(2026, 10, 9, 14, 30, 0), row.first_reported_at
      assert_equal row.first_reported_at, row.last_reported_at
      assert_equal 1, row.report_count
      assert_equal SES_ID, row.message_id
    end
  end

  %w[Transient Undetermined].each do |bounce_type|
    test "a #{bounce_type.downcase} bounce records no address" do
      post_event(bounce_event(bounce_type, sub_type: bounce_type == "Undetermined" ? "Undetermined" : "General"))

      assert_response :success
      assert_equal 0, EmailSuppression.count
    end
  end

  test "another report adds to the count, and a redelivered report does not" do
    travel_to(Time.zone.local(2026, 10, 1, 9, 0, 0)) { post_event(bounce_event("Permanent", message_id: "ses-1")) }
    travel_to(Time.zone.local(2026, 10, 9, 14, 30, 0)) do
      post_event(bounce_event("Permanent", sub_type: "General", message_id: "ses-2"))
    end

    row = EmailSuppression.find_by!(email: "ranger@example.com")
    assert_equal 2, row.report_count
    assert_equal Time.zone.local(2026, 10, 1, 9, 0, 0), row.first_reported_at
    assert_equal Time.zone.local(2026, 10, 9, 14, 30, 0), row.last_reported_at
    assert_equal "General", row.sub_type
    assert_equal "ses-2", row.message_id

    # SNS delivers at least once: the same report again counts for nothing.
    travel_to(Time.zone.local(2026, 10, 10, 8, 0, 0)) do
      assert_no_changes -> { row.reload.attributes } do
        post_event(bounce_event("Permanent", sub_type: "General", message_id: "ses-2"))
      end
    end
    assert_equal 1, EmailSuppression.count
  end

  test "a report naming the address in another case or with spaces finds the same row" do
    post_event(bounce_event("Permanent", message_id: "ses-1"))
    post_event(bounce_event("Permanent", email: "  Ranger@Example.COM ", message_id: "ses-2"))

    assert_equal 1, EmailSuppression.count
    assert_equal 2, EmailSuppression.find_by!(email: "ranger@example.com").report_count
  end

  # SES fills emailAddress from the bounce's Final-Recipient, which a forwarder
  # can change; the destination holds the address the Clubhouse sent to.
  test "the one address the email was sent to is recorded, not a forwarder's" do
    post_event(bounce_event("Permanent", email: "ranger@forwarded.example.org",
                                         destination: ["Ranger Name <ranger@example.com>"]))

    assert_equal ["ranger@example.com"], EmailSuppression.pluck(:email)
    # The mail log is still matched on the reported address, so it misses: the documented mismatch.
    assert_not @mail_log.reload.did_bounce
  end

  test "with no destination, or two, the reported address is recorded" do
    post_event(bounce_event("Permanent", email: "first@example.org"))
    post_event(bounce_event("Permanent", email: "second@example.org",
                                         destination: ["ranger@example.com", "lead@example.com"]))

    assert_equal %w[first@example.org second@example.org], EmailSuppression.order(:email).pluck(:email)
  end

  test "a destination that does not parse leaves the reported address" do
    post_event(bounce_event("Permanent", email: "reported@example.org", destination: ["Ranger Name"]))

    assert_equal ["reported@example.org"], EmailSuppression.pluck(:email)
  end

  test "a slack bounce records no address" do
    post_event(bounce_event("Permanent", email: "nobody@burningman.slack.com"))

    assert_response :success
    assert_equal 0, EmailSuppression.count
  end

  test "a forged signature records no address" do
    envelope = notification_envelope(bounce_event("Permanent"))
    envelope["Signature"] = ["not a signature"].pack("m0")

    post_json(envelope)

    assert_response :forbidden
    assert_equal 0, EmailSuppression.count
  end

  test "a report from somebody else's topic records no address" do
    post_event(bounce_event("Permanent"), topic: "arn:aws:sns:us-west-2:999999999999:not-ours")

    assert_response :forbidden
    assert_equal 0, EmailSuppression.count
  end

  # =========================================================================
  # A broadcast email's bounce
  # =========================================================================

  # In every type, this copy did not arrive.
  %w[Permanent Transient Undetermined].each do |bounce_type|
    test "a #{bounce_type.downcase} bounce of a broadcast email marks its message bounced" do
      sent = broadcast_email(@listener)

      post_event(broadcast_bounce(bounce_type))

      assert_response :success
      assert_equal Broadcast::STATUS_BOUNCED, sent.reload.status
    end
  end

  # SES gives every email its own id, so no two rows share one. Sharing it here
  # shows the match is the person, the broadcast and the channel as well, never
  # the id alone; the copy under another id shows the id counts too.
  test "a bounce marks only the copy it names" do
    sent = broadcast_email(@listener)
    text = sent.dup.tap { |copy| copy.update!(address_type: "sms", address: @listener.sms_number) }
    neighbour = sent.dup.tap { |copy| copy.update!(person_id: rbs_person("Neighbour").id) }
    elsewhere = sent.dup.tap { |copy| copy.update!(broadcast_id: rbs_broadcast(sender: @person).id) }
    resent = sent.dup.tap { |copy| copy.update!(message_id: "#{SES_ID}-resent") }

    post_event(broadcast_bounce)

    assert_equal Broadcast::STATUS_BOUNCED, sent.reload.status
    [text, neighbour, elsewhere, resent].each do |message|
      assert_equal Broadcast::STATUS_SENT, message.reload.status
    end
  end

  # Only a message still sent moves; any other status stays as it is.
  test "a bounce leaves a message in another status alone" do
    held = broadcast_email(@listener, status: Broadcast::STATUS_SEND_UNCONFIRMED)

    post_event(broadcast_bounce)

    assert_equal Broadcast::STATUS_SEND_UNCONFIRMED, held.reload.status
  end

  test "a repeated bounce report changes nothing" do
    sent = broadcast_email(@listener)
    post_event(broadcast_bounce)

    assert_no_changes -> { BroadcastMessage.order(:id).pluck(:id, :status) } do
      post_event(broadcast_bounce)
    end

    assert_response :success
    assert_equal Broadcast::STATUS_BOUNCED, sent.reload.status
  end

  # The bounced address is the test address, which is nobody's email: the
  # person comes from the mail log row.
  test "a bounce from the test address marks the copy sent there" do
    test_address = "test+#{@listener.id}@example.com"
    sent = broadcast_email(@listener, to: test_address)

    post_event(broadcast_bounce("Permanent", email: test_address))

    assert_equal Broadcast::STATUS_BOUNCED, sent.reload.status
  end

  test "a bounce of mail that was not a broadcast changes no broadcast message" do
    sent = broadcast_email(@listener)

    post_event(bounce_event("Transient"))

    assert_response :success
    assert @mail_log.reload.did_bounce
    assert_equal Broadcast::STATUS_SENT, sent.reload.status
  end

  test "a bounce naming an id no mail log row holds changes no broadcast message" do
    sent = broadcast_email(@listener)

    post_event(broadcast_bounce(message_id: "#{SES_ID}-unknown"))

    assert_response :success
    assert_equal Broadcast::STATUS_SENT, sent.reload.status
  end

  # A bounce is not a failure: nothing recounts it, and a Retry never sends it.
  test "a bounced broadcast email is not a failure" do
    broadcast_email(@listener)
    @broadcast.update!(sent_email: true)

    assert_no_changes -> {
      @broadcast.reload
      [@broadcast.email_failed, @broadcast.failed?, Broadcast.with_failures.exists?(@broadcast.id),
       @broadcast.failed_messages.pluck(:id), @broadcast.retryable?]
    } do
      post_event(broadcast_bounce("Permanent"))
    end

    assert_equal 1, @broadcast.bounced_messages.count
  end

  # =========================================================================
  # Complaint
  # =========================================================================

  test "a complaint marks the mail log and the action log" do
    post_event({ "notificationType" => "Complaint",
               "mail" => { "messageId" => "message-1@example.com" },
               "complaint" => { "complainedRecipients" => [{ "emailAddress" => "ranger@example.com" }] } })

    assert_response :success
    assert @mail_log.reload.did_complain
    assert_equal 1, ActionLog.where(event: "email-complaint", target_person_id: @person.id).count
  end

  # A complaint means the email arrived.
  test "a complaint about a broadcast email leaves its message sent" do
    sent = broadcast_email(@listener)

    post_event({ "notificationType" => "Complaint",
               "mail" => { "messageId" => SES_ID },
               "complaint" => { "complainedRecipients" => [{ "emailAddress" => @listener.email }] } })

    assert_response :success
    assert MailLog.find_by!(message_id: SES_ID).did_complain
    assert_equal Broadcast::STATUS_SENT, sent.reload.status
  end

  test "a complaint records the address as a spam report" do
    post_event(complaint_event(sub_type: EmailSuppression::ON_ACCOUNT_SUPPRESSION_LIST))

    row = EmailSuppression.find_by!(email: "ranger@example.com")
    assert_equal EmailSuppression::COMPLAINT, row.reason
    assert_equal EmailSuppression::ON_ACCOUNT_SUPPRESSION_LIST, row.sub_type
    assert_equal "message-1@example.com", row.message_id
  end

  test "a complaint turns a bounced address into a spam report" do
    suppress_email("ranger@example.com", message_id: "ses-bounce")

    post_event(complaint_event)

    row = EmailSuppression.find_by!(email: "ranger@example.com")
    assert_equal EmailSuppression::COMPLAINT, row.reason
    assert_equal 2, row.report_count
  end

  # SES answers a send to an address its list holds for a complaint with a
  # Permanent OnAccountSuppressionList bounce.
  test "a bounce never turns a spam report back into a bounce" do
    suppress_email("ranger@example.com", reason: EmailSuppression::COMPLAINT, message_id: "ses-complaint")

    post_event(bounce_event("Permanent", sub_type: EmailSuppression::ON_ACCOUNT_SUPPRESSION_LIST,
                                         message_id: SES_ID))

    row = EmailSuppression.find_by!(email: "ranger@example.com")
    assert_equal EmailSuppression::COMPLAINT, row.reason
    assert_equal EmailSuppression::ON_ACCOUNT_SUPPRESSION_LIST, row.sub_type
    assert_equal 2, row.report_count
  end

  # =========================================================================
  # An SES event published as the whole body rather than wrapped
  # =========================================================================

  test "an eventType is read the same as a notificationType" do
    post_event({ "eventType" => "Bounce",
               "mail" => { "messageId" => "message-1@example.com" },
               "bounce" => {
                 "bounceType" => "Permanent",
                 "bouncedRecipients" => [{ "emailAddress" => "ranger@example.com" }]
               } })

    assert @mail_log.reload.did_bounce
  end

  # =========================================================================
  # Anything not actually from our topic
  # =========================================================================

  test "a forged signature changes nothing" do
    envelope = notification_envelope(bounce_event("Permanent"))
    envelope["Signature"] = ["not a signature"].pack("m0")

    post_json(envelope)

    assert_response :forbidden
    assert_not @mail_log.reload.did_bounce
    assert_not @person.reload.is_bouncing
  end

  test "a signed message from somebody else's topic is refused" do
    post_event(bounce_event("Permanent"), topic: "arn:aws:sns:us-west-2:999999999999:not-ours")

    assert_response :forbidden
    assert_not @person.reload.is_bouncing
  end

  test "nothing is accepted until the topic is configured" do
    Setting.find_by(name: Setting::SES_SNS_TOPIC_ARN).destroy!

    post_event(bounce_event("Permanent"))

    assert_response :forbidden
    assert_equal 1, ErrorLog.where(error_type: "sns-topic-not-configured").count
  end

  test "a certificate served from outside AWS is refused" do
    envelope = notification_envelope(bounce_event("Permanent"))
    envelope["SigningCertURL"] = "https://example.com/evil.pem"
    envelope["Signature"] = sign(envelope, SnsMessage::SIGNED_KEYS["Notification"])

    post_json(envelope)

    assert_response :forbidden
    assert_empty @fetched
  end

  test "a body that is not JSON is refused" do
    post infrastructure_aws_sns_url, params: "not json", headers: { "CONTENT_TYPE" => "application/json" }

    assert_response :bad_request
  end

  # =========================================================================
  # Subscription
  # =========================================================================

  test "a subscription confirmation is acknowledged by fetching its URL" do
    subscribe_url = "https://sns.us-west-2.amazonaws.com/?Action=ConfirmSubscription&Token=xyz"
    envelope = {
      "Type" => "SubscriptionConfirmation",
      "MessageId" => "sub-1",
      "Token" => "xyz",
      "TopicArn" => TOPIC,
      "Message" => "You have chosen to subscribe.",
      "SubscribeURL" => subscribe_url,
      "Timestamp" => Time.now.utc.iso8601,
      "SignatureVersion" => "1",
      "SigningCertURL" => CERT_URL
    }
    envelope["Signature"] = sign(envelope, SnsMessage::SIGNED_KEYS["SubscriptionConfirmation"])

    post_json(envelope)

    assert_response :success
    assert_includes @fetched, subscribe_url
  end

  test "an unsigned subscription confirmation is not fetched" do
    envelope = {
      "Type" => "SubscriptionConfirmation",
      "MessageId" => "sub-2",
      "Token" => "xyz",
      "TopicArn" => TOPIC,
      "Message" => "You have chosen to subscribe.",
      "SubscribeURL" => "https://sns.us-west-2.amazonaws.com/?Action=ConfirmSubscription",
      "Timestamp" => Time.now.utc.iso8601,
      "SignatureVersion" => "1",
      "SigningCertURL" => CERT_URL,
      "Signature" => ["nope"].pack("m0")
    }

    post_json(envelope)

    assert_response :forbidden
    # The certificate is fetched to check the signature; the subscription is not.
    assert_equal [CERT_URL], @fetched
  end

  private

  # A broadcast email sent to the test address, logged under the id SES gave it.
  def test_address_log
    MailLog.create!(message_id: SES_ID, from_email: "do-not-reply@burningman.org",
                    to_email: "test+#{@person.id}@example.com", was_sent: true)
  end

  # A broadcast email SES took, written as Rbs.record_email_batch writes one:
  # its message row and its mail log row, under the id SES gave it and the
  # address it went to.
  def broadcast_email(person, to: person.email, status: Broadcast::STATUS_SENT)
    BroadcastMessage.record_outbound(@broadcast.id, "email",
                                     [{ person_id: person.id, address: to, status:, message_id: SES_ID }])
    MailLog.record_ses_sends([{ person_id: person.id, to_email: to, message_id: SES_ID }],
                             sender_id: @person.id, from_email: "do-not-reply@burningman.org",
                             broadcast_id: @broadcast.id)
    BroadcastMessage.find_by!(broadcast_id: @broadcast.id, person_id: person.id, address_type: "email")
  end

  # A bounce of the broadcast email broadcast_email wrote for @listener.
  def broadcast_bounce(bounce_type = "Transient", email: @listener.email, message_id: SES_ID)
    bounce_event(bounce_type, email:, message_id:)
  end

  # sub_type: and destination: are left out of the report unless given.
  def bounce_event(bounce_type, email: "ranger@example.com", message_id: "message-1@example.com",
                   sub_type: nil, destination: nil)
    {
      "notificationType" => "Bounce",
      "mail" => { "messageId" => message_id, "destination" => destination }.compact,
      "bounce" => {
        "bounceType" => bounce_type,
        "bounceSubType" => sub_type,
        "bouncedRecipients" => [{ "emailAddress" => email }]
      }.compact
    }
  end

  def complaint_event(email: "ranger@example.com", message_id: "message-1@example.com", sub_type: nil)
    {
      "notificationType" => "Complaint",
      "mail" => { "messageId" => message_id },
      "complaint" => { "complaintSubType" => sub_type, "complainedRecipients" => [{ "emailAddress" => email }] }
    }
  end

  def notification_envelope(event, topic: TOPIC)
    envelope = {
      "Type" => "Notification",
      "MessageId" => "envelope-#{SecureRandom.hex(4)}",
      "TopicArn" => topic,
      "Message" => event.to_json,
      "Timestamp" => Time.now.utc.iso8601,
      "SignatureVersion" => "1",
      "SigningCertURL" => CERT_URL
    }
    envelope["Signature"] = sign(envelope, SnsMessage::SIGNED_KEYS["Notification"])
    envelope
  end

  def post_event(event, topic: TOPIC)
    post_json(notification_envelope(event, topic: topic))
  end

  def post_json(envelope)
    post infrastructure_aws_sns_url,
         params: envelope.to_json,
         headers: { "CONTENT_TYPE" => "application/json" }
  end

  # Sign a message the way SNS does: the covered fields, in order, each as
  # "key\nvalue\n".
  def sign(envelope, keys)
    canonical = keys.filter_map { |key| "#{key}\n#{envelope[key]}\n" if envelope.key?(key) }.join
    [KEY.sign(OpenSSL::Digest::SHA1.new, canonical)].pack("m0")
  end

  # Stand in for the two things this endpoint fetches -- the signing
  # certificate and a subscription URL -- and record what was asked for, so a
  # test can show that a URL outside AWS was never reached.
  def stub_fetch_aws
    fetched = @fetched
    pem = CERTIFICATE
    @original_fetch = SnsMessage.method(:fetch_aws)

    SnsMessage.define_singleton_method(:fetch_aws) do |url|
      return nil unless URI.parse(url.to_s).host.to_s.match?(SnsMessage::AWS_HOST)

      fetched << url
      url == CERT_URL ? pem : "OK"
    end
  end

  def restore_fetch_aws
    SnsMessage.singleton_class.remove_method(:fetch_aws)
    SnsMessage.define_singleton_method(:fetch_aws, @original_fetch)
  end
end
