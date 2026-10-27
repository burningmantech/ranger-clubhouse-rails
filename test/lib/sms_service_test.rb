# frozen_string_literal: true

require "test_helper"

# The send path, the receipts and the recheck. Every text goes through the
# Messaging Service with the Messages API. SmsService.broadcast, one Notify
# notification per service in TwilioServiceId with the numbers shared out
# between them, has had no caller since broadcasts moved off it, and goes
# before Notify's end of life on 2027-01-31.
class SmsServiceTest < ActiveSupport::TestCase
  include FakeTwilioTestHelper
  include EnvTestHelper

  TWO_SERVICES = { "ISservice0001" => "Ranger Alerts", "ISservice0002" => "Ranger News" }.freeze

  # A number as Notify takes it.
  def sms_binding(number) = { binding_type: "sms", address: number }.to_json

  # A text the Clubhouse recorded sending this long ago.
  def text_row(status, sid, sent_ago)
    BroadcastMessage.create!(person_id: person(:active_ranger).id, address_type: "sms", address: "+14155550101",
                             direction: "outbound", status:, message_id: sid, created_at: sent_ago.ago)
  end

  test "shares the numbers out across the Notify services, each in E.164" do
    configure_twilio(service_ids: "ISservice0001,ISservice0002")
    fake = FakeTwilioClient.new(services: TWO_SERVICES)

    sent = with_fake_twilio(fake) do
      SmsService.broadcast(["(415) 555-0101", "+14155550102", "415-555-0103"], "Muster at HQ")
    end

    assert_equal "sent", sent
    assert_equal [{ service: "ISservice0001", body: "Muster at HQ",
                    to_binding: [sms_binding("+14155550101"), sms_binding("+14155550102")] },
                  { service: "ISservice0002", body: "Muster at HQ", to_binding: [sms_binding("+14155550103")] }],
                 fake.notifications
  end

  test "a service left with no numbers is not asked" do
    configure_twilio(service_ids: "ISservice0001,ISservice0002")
    fake = FakeTwilioClient.new(services: TWO_SERVICES)

    with_fake_twilio(fake) { SmsService.broadcast(["+14155550101"], "Your Clubhouse verification code is: 1234") }

    assert_equal ["ISservice0001"], fake.notifications.pluck(:service)
  end

  test "a refusal is raised as an SmsException naming its service, after the services before it sent" do
    configure_twilio(service_ids: "ISservice0001,ISmissing0002")
    fake = FakeTwilioClient.new

    error = assert_raises(SmsException) do
      with_fake_twilio(fake) { SmsService.broadcast(["+14155550101", "+14155550102"], "Muster at HQ") }
    end

    assert_instance_of Twilio::REST::RestError, error.cause
    assert_equal 20404, error.cause.code
    assert_equal "service ISmissing0002: #{error.cause.message}", error.message
    assert_equal ["ISservice0001"], fake.notifications.pluck(:service)
  end

  test "a single text goes through the Messaging Service, in E.164, held two hours at most, and answers its SID" do
    configure_twilio
    fake = FakeTwilioClient.new

    sid = with_fake_twilio(fake) { SmsService.send_text("(415) 555-0101", "Your Clubhouse verification code is: 1234") }

    assert_equal format("SM%032d", 1), sid
    assert_equal [{ messaging_service_sid: FakeTwilioClient::MESSAGING_SERVICE_SID, to: "+14155550101",
                    body: "Your Clubhouse verification code is: 1234", validity_period: 7200 }],
                 fake.created_texts
    assert_empty fake.notifications, "never through Notify"
  end

  test "a single text Twilio refused raises an SmsException, the refusal kept as its cause" do
    configure_twilio
    fake = FakeTwilioClient.new(errors: { message_create: FakeTwilioClient.refusal(21610, "Attempt to send to unsubscribed recipient") })

    error = assert_raises(SmsException) { with_fake_twilio(fake) { SmsService.send_text("+14155550101", "Muster at HQ") } }

    assert_not_kind_of SmsException::Unconfirmed, error
    assert_equal 21610, error.cause.code
  end

  test "a single text Twilio may have taken without answering raises SmsException::Unconfirmed" do
    configure_twilio
    fake = FakeTwilioClient.new(errors: { message_create: FakeTwilioClient.read_timeout })

    error = assert_raises(SmsException::Unconfirmed) do
      with_fake_twilio(fake) { SmsService.send_text("+14155550101", "Muster at HQ") }
    end

    assert_instance_of Faraday::TimeoutError, error.cause.cause
  end

  test "a single text asks Twilio nothing while the Messaging Service is not set" do
    configure_twilio(messaging_service_id: nil)
    fake = FakeTwilioClient.new

    error = assert_raises(SmsException) { with_fake_twilio(fake) { SmsService.send_text("+14155550101", "Muster at HQ") } }

    assert_equal "TwilioMessagingServiceId is not set", error.message
    assert_empty fake.asked
  end

  test "a text recorded in a row asks Twilio for a receipt at this server's address, the row's id in the query" do
    configure_twilio
    fake = FakeTwilioClient.new

    with_fake_twilio(fake) { SmsService.send_text("+14155550101", "Muster at HQ", receipt_for: 42) }

    assert_equal ["https://example.com/infrastructure/sms/status?message=42"], fake.created_texts.pluck(:status_callback)
  end

  # Asking from an address Twilio cannot reach would raise an 11200 alert on
  # the live account for every text.
  test "a server Twilio cannot reach asks for no receipt" do
    configure_twilio
    fake = FakeTwilioClient.new
    original = Rails.application.config.action_mailer.default_url_options
    Rails.application.config.action_mailer.default_url_options = { host: "localhost", port: 3000 }

    with_fake_twilio(fake) { SmsService.send_text("+14155550101", "Muster at HQ", receipt_for: 42) }

    assert_nil SmsService.receipt_address
    assert_not fake.created_texts.sole.key?(:status_callback)
  ensure
    Rails.application.config.action_mailer.default_url_options = original
  end

  test "a receipt reads as delivered, or why not, and anything earlier as sent" do
    read = ->(status, error_code = nil) do
      SmsService.process_status_callback({ MessageSid: "SMabc", MessageStatus: status, ErrorCode: error_code }, "7")
    end

    assert_equal SmsService::StatusCallback.new(row_id: "7", sid: "SMabc", status: Broadcast::STATUS_DELIVERED),
                 read.call("delivered")
    assert_equal [Broadcast::STATUS_BLOCKED, Broadcast::STATUS_BOUNCED, Broadcast::STATUS_BOUNCED, Broadcast::STATUS_FAILED],
                 [read.call("undelivered", "30004"), read.call("undelivered", "30005"), read.call("failed", "30007"),
                  read.call("failed", "30008")].map(&:status)
    assert_equal [Broadcast::STATUS_SENT] * 3, %w[queued sending sent].map { |status| read.call(status).status }
  end

  test "the recheck asks Twilio about texts waiting 12 hours to 3 days, and moves them as a receipt would" do
    configure_twilio
    waiting = text_row(Broadcast::STATUS_SENT, "SMwaiting", 13.hours)
    code = text_row(Broadcast::STATUS_VERIFY, "SMcode", 1.day)
    going = text_row(Broadcast::STATUS_SENT, "SMgoing", 20.hours)
    untouched = [text_row(Broadcast::STATUS_SENT, "SMrecent", 1.hour), text_row(Broadcast::STATUS_SENT, "SMold", 4.days),
                 text_row(Broadcast::STATUS_DELIVERED, "SMdone", 13.hours), text_row(Broadcast::STATUS_SENT, nil, 13.hours)]
    fake = FakeTwilioClient.new(sent_texts: { "SMwaiting" => FakeTwilioClient.text(status: "delivered"),
                                              "SMcode" => FakeTwilioClient.text(status: "undelivered", error_code: 30006),
                                              "SMgoing" => FakeTwilioClient.text(status: "sent") })

    moved = with_fake_twilio(fake) { SmsService.recheck_unfinished_texts }

    assert_equal 2, moved
    assert_equal 3, fake.asked.count(:message_fetch), "only the texts in the window still waiting"
    assert_equal [Broadcast::STATUS_DELIVERED, Broadcast::STATUS_BOUNCED, Broadcast::STATUS_SENT],
                 [waiting, code, going].map { |row| row.reload.status }
    assert_equal untouched.map(&:status), untouched.map { |row| row.reload.status }
  end

  test "the recheck skips a text Twilio no longer has, and stops at a call Twilio does not answer" do
    configure_twilio
    gone = text_row(Broadcast::STATUS_SENT, "SMgone", 14.hours)
    kept = text_row(Broadcast::STATUS_SENT, "SMkept", 13.hours)
    answers = { "SMkept" => FakeTwilioClient.text(status: "delivered") }

    with_fake_twilio(FakeTwilioClient.new(sent_texts: answers)) { SmsService.recheck_unfinished_texts }

    assert_equal [Broadcast::STATUS_SENT, Broadcast::STATUS_DELIVERED], [gone.reload.status, kept.reload.status]

    kept.update_columns(status: Broadcast::STATUS_SENT)
    silent = FakeTwilioClient.new(sent_texts: answers, errors: { message_fetch: FakeTwilioClient.read_timeout })

    assert_equal 0, with_fake_twilio(silent) { SmsService.recheck_unfinished_texts }
    assert_equal 1, silent.asked.count(:message_fetch), "the next run asks again"
    assert_equal [Broadcast::STATUS_SENT] * 2, [gone.reload.status, kept.reload.status]
    assert_equal 1, ErrorLog.where(error_type: "sms-recheck-exception").count
  end

  test "the recheck asks Twilio nothing on the training server" do
    configure_twilio
    row = text_row(Broadcast::STATUS_SENT, "SMwaiting", 13.hours)
    fake = FakeTwilioClient.new(sent_texts: { "SMwaiting" => FakeTwilioClient.text(status: "delivered") })

    with_env("RANGER_CLUBHOUSE_GROUNDHOG_DAY_TIME" => "2025-08-30 12:00") do
      with_fake_twilio(fake) { SmsService.recheck_unfinished_texts }
    end

    assert_empty fake.asked
    assert_equal Broadcast::STATUS_SENT, row.reload.status
  end

  # Every test above hands the send its client through
  # TwilioAccount.build_client; this is the client it builds outside a test.
  test "a broadcast's client gives up on Twilio after five seconds" do
    client = TwilioAccount.build_client("deadbeef", "token-never-shown")

    assert_equal 5, client.http_client.timeout
  end
end
