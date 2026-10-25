# frozen_string_literal: true

require "test_helper"

class Infrastructure::SmsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @person = person(:active_ranger)
    @person.update_columns(sms_number: "+15551234567", sms_verified: true, sms_stopped: false)
  end

  # =========================================================================
  # Inbound: STOP commands
  # =========================================================================

  test "inbound STOP marks number as stopped" do
    post infrastructure_sms_inbound_url, params: { From: "+15551234567", Body: "STOP" }

    @person.reload
    assert @person.sms_stopped?
  end

  test "inbound quit marks number as stopped" do
    post infrastructure_sms_inbound_url, params: { From: "+15551234567", Body: "quit" }

    @person.reload
    assert @person.sms_stopped?
  end

  # =========================================================================
  # Inbound: START commands
  # =========================================================================

  test "inbound START re-subscribes" do
    @person.update_columns(sms_stopped: true)

    post infrastructure_sms_inbound_url, params: { From: "+15551234567", Body: "START" }

    assert_response :success
    @person.reload
    assert_not @person.sms_stopped?
  end

  test "inbound subscribe re-subscribes" do
    @person.update_columns(sms_stopped: true)

    post infrastructure_sms_inbound_url, params: { From: "+15551234567", Body: "subscribe" }

    @person.reload
    assert_not @person.sms_stopped?
  end

  # =========================================================================
  # Inbound: HELP
  # =========================================================================

  test "inbound HELP returns help message" do
    post infrastructure_sms_inbound_url, params: { From: "+15551234567", Body: "HELP" }

    assert_response :success
    assert_includes response.body, "Commands available"
  end

  # =========================================================================
  # Inbound: NEXT
  # =========================================================================

  test "inbound NEXT with no shifts returns no shifts message" do
    post infrastructure_sms_inbound_url, params: { From: "+15551234567", Body: "NEXT" }

    assert_response :success
    assert_includes response.body, "No upcoming shifts"
  end

  # =========================================================================
  # Inbound: Unknown phone
  # =========================================================================

  test "inbound from unknown phone records unknown and replies" do
    assert_difference("BroadcastMessage.count") do
      post infrastructure_sms_inbound_url, params: { From: "+19999999999", Body: "hello" }
    end

    assert_response :success
    assert_includes response.body, "cannot be found"
  end

  # =========================================================================
  # Inbound: Unknown command
  # =========================================================================

  test "inbound unknown command replies with error" do
    post infrastructure_sms_inbound_url, params: { From: "+15551234567", Body: "foobar" }

    assert_response :success
    assert_includes response.body, "not understood"
  end

  # =========================================================================
  # Inbound: Missing phone
  # =========================================================================

  test "inbound without phone number returns 422" do
    post infrastructure_sms_inbound_url, params: { From: "", Body: "hello" }

    assert_response :unprocessable_entity
  end

  # =========================================================================
  # Crawler rejection
  # =========================================================================

  test "rejects known web crawlers" do
    post infrastructure_sms_inbound_url,
         params: { From: "+15551234567", Body: "hello" },
         headers: { "User-Agent" => "Mozilla/5.0 (compatible; bingbot/2.0)" }

    assert_response :forbidden
  end

  # =========================================================================
  # Message logging
  # =========================================================================

  test "inbound records both inbound and outbound messages" do
    # inbound message + outbound reply = 2 messages
    assert_difference("BroadcastMessage.count", 2) do
      post infrastructure_sms_inbound_url, params: { From: "+15551234567", Body: "HELP" }
    end
  end
end
