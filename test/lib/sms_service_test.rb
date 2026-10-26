# frozen_string_literal: true

require "test_helper"

# The send path as it stands: every text goes through Twilio Notify, one
# notification per service in TwilioServiceId with the numbers shared out
# between them. Notify reaches its end of life on 2027-01-31; these describe
# what moves off it.
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

  # Every test above hands the broadcast its client through
  # TwilioAccount.build_client; this is the client it builds outside a test.
  test "a broadcast's client gives up on Twilio after five seconds" do
    client = TwilioAccount.build_client("deadbeef", "token-never-shown")

    assert_equal 5, client.http_client.timeout
  end
end
