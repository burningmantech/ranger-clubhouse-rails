# frozen_string_literal: true

require "test_helper"

class TwilioStatusTest < ActiveSupport::TestCase
  include CacheTestHelper
  include FakeTwilioTestHelper

  test "asks Twilio nothing until the account SID and auth token are set" do
    fake = FakeTwilioClient.new

    with_fake_twilio(fake) { assert_nil TwilioStatus.fetch }

    assert_empty fake.asked
  end

  test "reads the account, its balance, each service, the day's texts and the alerts" do
    travel_to Time.utc(2026, 10, 25, 3) do
      configure_twilio(service_ids: "ISservice0001,ISmissing0002")
      filtered = FakeTwilioClient::Alert.new(Time.utc(2026, 10, 25, 2), "30007", "warning",
                                             "ErrorCode=30007&Msg=Message+filtered+by+the+carrier&LogLevel=WARN")
      plain = FakeTwilioClient::Alert.new(Time.utc(2026, 10, 25, 1), "11200", "error", "HTTP retrieval failure")
      texts = [FakeTwilioClient.text, FakeTwilioClient.text, FakeTwilioClient.text(status: "undelivered"),
               FakeTwilioClient.text(status: "received", direction: "inbound"),
               # Listed, since Twilio filters by date, but outside the 24 hours.
               FakeTwilioClient.text(status: "failed", date_sent: 30.hours.ago)]
      fake = FakeTwilioClient.new(texts:, alerts: [filtered, plain])

      status = with_fake_twilio(fake) { TwilioStatus.fetch }

      assert_equal({ value: { name: "Black Rock Rangers", status: "active", type: "Full", subaccount: false } },
                   status[:account])
      assert_equal({ value: { amount: "412.37", currency: "USD" } }, status[:balance])
      assert_equal({ value: { name: "Ranger Alerts", messaging_service: FakeTwilioClient::MESSAGING_SERVICE_SID,
                              incoming_url: FakeTwilioClient::CLUBHOUSE2_INCOMING, fallback_url: nil,
                              defers_to_number: false },
                     id: "ISservice0001" }, status[:services].first)
      # A service Twilio does not know is an answer of its own; the rest still came.
      assert_equal "The requested resource /Services/ISmissing0002 was not found (Twilio error 20404)",
                   status[:services].last[:error]
      assert_equal({ value: { counts: { "delivered" => 2, "undelivered" => 1, "received" => 1 }, sampled: false } },
                   status[:texts])
      # Twilio is asked for the UTC date the window opens.
      assert_equal "2026-10-24", fake.params[:messages][:date_sent_after]
      assert_equal [{ at: Time.utc(2026, 10, 25, 2), code: 30007, level: "warning", text: "Message filtered by the carrier" },
                    { at: Time.utc(2026, 10, 25, 1), code: 11200, level: "error", text: "HTTP retrieval failure" }],
                   status[:alerts][:value]
      assert_equal({ start_date: Time.utc(2026, 10, 24, 3), limit: TwilioStatus::ALERT_LIMIT }, fake.params[:alerts])
    end
  end

  test "a subaccount's balance is not asked for: its main account keeps it" do
    configure_twilio
    # A subaccount: another account owns it, not its own SID.
    subaccount = FakeTwilioClient::MAIN_ACCOUNT.with(owner_account_sid: "feedface")
    fake = FakeTwilioClient.new(account: subaccount)

    status = with_fake_twilio(fake) { TwilioStatus.fetch }

    assert status[:account][:value][:subaccount]
    assert_equal({ value: { main_account: true } }, status[:balance])
    assert_not_includes fake.asked, :balance
  end

  test "a full page of texts is counted as a sample" do
    configure_twilio
    fake = FakeTwilioClient.new(texts: Array.new(TwilioStatus::MESSAGE_LIMIT) { FakeTwilioClient.text })

    status = with_fake_twilio(fake) { TwilioStatus.fetch }

    assert status[:texts][:value][:sampled]
  end

  test "a full page that reaches back past the 24 hours holds all of them" do
    configure_twilio
    texts = Array.new(TwilioStatus::MESSAGE_LIMIT - 1) { FakeTwilioClient.text } +
            [FakeTwilioClient.text(date_sent: 30.hours.ago)]
    fake = FakeTwilioClient.new(texts:)

    status = with_fake_twilio(fake) { TwilioStatus.fetch }

    assert_equal({ counts: { "delivered" => TwilioStatus::MESSAGE_LIMIT - 1 }, sampled: false }, status[:texts][:value])
  end

  test "an id Twilio cannot be asked about is answered for without asking" do
    configure_twilio(service_ids: "ISservice0001, ISservice0002,,ISservice0003")
    fake = FakeTwilioClient.new

    status = with_fake_twilio(fake) { TwilioStatus.fetch }

    assert_equal ["ISservice0001", " ISservice0002", "", "ISservice0003"], status[:services].pluck(:id)
    assert_equal [SmsManagement::UNUSABLE_ID] * 2, status[:services][1..2].pluck(:error)
    assert_equal 2, fake.asked.count(:services)
  end

  test "once Twilio cannot be reached, nothing more is asked" do
    configure_twilio
    fake = FakeTwilioClient.new(errors: { account: Twilio::REST::TwilioError.new("Failed to open TCP connection") })

    status = with_fake_twilio(fake) { TwilioStatus.fetch }

    assert_equal [:account], fake.asked
    [status[:account], status[:balance], status[:texts], status[:alerts], *status[:services]].each do |answer|
      assert_equal "Could not reach Twilio: Failed to open TCP connection", answer[:error]
    end
  end

  test "a slow answer fails alone, and a read missing one is not cached" do
    configure_twilio
    fake = FakeTwilioClient.new(errors: { messages: FakeTwilioClient.read_timeout })

    with_cache_store do
      status = with_fake_twilio(fake) { TwilioStatus.fetch }

      assert_equal "Could not reach Twilio: Net::ReadTimeout with #<TCPSocket:(closed)>", status[:texts][:error]
      # Asked after the slow one, and answered.
      assert_equal [], status[:alerts][:value]

      with_fake_twilio(fake) { TwilioStatus.fetch }

      assert_equal 2, fake.asked.count(:account)
    end
  end

  test "a read that could not reach Twilio is not cached" do
    configure_twilio
    fake = FakeTwilioClient.new(errors: { account: Twilio::REST::TwilioError.new("Failed to open TCP connection") })

    with_cache_store do
      with_fake_twilio(fake) { 2.times { TwilioStatus.fetch } }
    end

    assert_equal 2, fake.asked.count(:account)
  end

  test "asks once while the answer is cached, and again on refresh or a changed setting" do
    configure_twilio
    fake = FakeTwilioClient.new

    with_cache_store do
      with_fake_twilio(fake) do
        2.times { TwilioStatus.fetch }
        assert_equal 1, fake.asked.count(:account)

        TwilioStatus.fetch(refresh: true)
        assert_equal 2, fake.asked.count(:account)

        # The cache key follows the settings, so a corrected token is asked
        # about at once rather than after the old answer runs out.
        Setting.find(Setting::TWILIO_AUTH_TOKEN).update!(value: "a-corrected-token")
        TwilioStatus.fetch
        assert_equal 3, fake.asked.count(:account)
      end
    end
  end
end
