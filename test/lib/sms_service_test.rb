# frozen_string_literal: true

require "test_helper"

# The send path. A broadcast still goes through Twilio Notify, one
# notification per service in TwilioServiceId with the numbers shared out
# between them, until it moves off before Notify's end of life on 2027-01-31.
# A single text (a verification code, a new-message alert) already goes
# through the Messaging Service with the Messages API.
class SmsServiceTest < ActiveSupport::TestCase
  include FakeTwilioTestHelper

  TWO_SERVICES = { "ISservice0001" => "Ranger Alerts", "ISservice0002" => "Ranger News" }.freeze

  # A number as Notify takes it.
  def sms_binding(number) = { binding_type: "sms", address: number }.to_json

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

  # Every test above hands the send its client through
  # TwilioAccount.build_client; this is the client it builds outside a test.
  test "a broadcast's client gives up on Twilio after five seconds" do
    client = TwilioAccount.build_client("deadbeef", "token-never-shown")

    assert_equal 5, client.http_client.timeout
  end
end
