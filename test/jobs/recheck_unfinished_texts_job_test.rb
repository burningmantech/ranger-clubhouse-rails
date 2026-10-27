# frozen_string_literal: true

require "test_helper"

class RecheckUnfinishedTextsJobTest < ActiveJob::TestCase
  include FakeTwilioTestHelper
  include EnvTestHelper

  # config/recurring.yml as Solid Queue reads it, on a server with env set.
  def recurring(env = {})
    with_env(env) { YAML.safe_load(ERB.new(Rails.root.join("config/recurring.yml").read).result) }
  end

  test "it is scheduled daily in production, and neither in development nor on the training server" do
    assert_equal ["RecheckUnfinishedTextsJob", "at 6am every day"],
                 recurring.dig("production", "recheck_unfinished_texts")&.values_at("class", "schedule")
    assert_nil recurring.dig("development", "recheck_unfinished_texts")
    assert_nil recurring("RANGER_CLUBHOUSE_GROUNDHOG_DAY_TIME" => "2025-08-30 12:00")
               .dig("production", "recheck_unfinished_texts")
  end

  test "it records what Twilio says of a text still waiting for its receipt" do
    configure_twilio
    row = BroadcastMessage.create!(person_id: person(:active_ranger).id, address_type: "sms", address: "+14155550101",
                                   direction: "outbound", status: Broadcast::STATUS_SENT, message_id: "SMwaiting",
                                   created_at: 13.hours.ago)
    fake = FakeTwilioClient.new(sent_texts: { "SMwaiting" => FakeTwilioClient.text(status: "delivered") })

    with_fake_twilio(fake) { RecheckUnfinishedTextsJob.perform_now }

    assert_equal Broadcast::STATUS_DELIVERED, row.reload.status
  end
end
