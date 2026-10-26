# frozen_string_literal: true

require "test_helper"

class Infrastructure::SmsControllerTest < ActionDispatch::IntegrationTest
  AUTH_TOKEN = "token-never-shown"
  # Where Clubhouse 2 has Twilio post the texts. A request Twilio signed for it
  # must not pass here.
  CLUBHOUSE2_ADDRESS = "https://ranger-clubhouse.burningman.org/api/sms/inbound"
  # Another server answering at the same path, as the training server does.
  ANOTHER_HOST = "another-server.example.org"

  setup do
    Setting.find_or_initialize_by(name: Setting::TWILIO_AUTH_TOKEN).update!(value: AUTH_TOKEN)
    @person = person(:active_ranger)
    @person.update_columns(sms_number: "+15551234567", sms_verified: true, sms_stopped: false)
  end

  # =========================================================================
  # Inbound: STOP commands
  # =========================================================================

  test "inbound STOP marks number as stopped" do
    post_signed({ From: "+15551234567", Body: "STOP" })

    @person.reload
    assert @person.sms_stopped?
  end

  test "inbound quit marks number as stopped" do
    post_signed({ From: "+15551234567", Body: "quit" })

    @person.reload
    assert @person.sms_stopped?
  end

  # =========================================================================
  # Inbound: START commands
  # =========================================================================

  test "inbound START re-subscribes" do
    @person.update_columns(sms_stopped: true)

    post_signed({ From: "+15551234567", Body: "START" })

    assert_response :success
    @person.reload
    assert_not @person.sms_stopped?
  end

  test "inbound subscribe re-subscribes" do
    @person.update_columns(sms_stopped: true)

    post_signed({ From: "+15551234567", Body: "subscribe" })

    @person.reload
    assert_not @person.sms_stopped?
  end

  # =========================================================================
  # Inbound: HELP
  # =========================================================================

  test "inbound HELP returns help message" do
    post_signed({ From: "+15551234567", Body: "HELP" })

    assert_response :success
    assert_includes response.body, "Commands available"
  end

  # =========================================================================
  # Inbound: NEXT
  # =========================================================================

  test "inbound NEXT with no shifts returns no shifts message" do
    post_signed({ From: "+15551234567", Body: "NEXT" })

    assert_response :success
    assert_includes response.body, "No upcoming shifts"
  end

  # =========================================================================
  # Inbound: Unknown phone
  # =========================================================================

  test "inbound from unknown phone records unknown and replies" do
    assert_difference("BroadcastMessage.count") do
      post_signed({ From: "+19999999999", Body: "hello" })
    end

    assert_response :success
    assert_includes response.body, "cannot be found"
  end

  # =========================================================================
  # Inbound: Unknown command
  # =========================================================================

  test "inbound unknown command replies with error" do
    post_signed({ From: "+15551234567", Body: "foobar" })

    assert_response :success
    assert_includes response.body, "not understood"
  end

  # =========================================================================
  # Inbound: Missing phone
  # =========================================================================

  test "inbound without phone number returns 422" do
    post_signed({ From: "", Body: "hello" })

    assert_response :unprocessable_entity
  end

  # =========================================================================
  # Crawler rejection
  # =========================================================================

  test "rejects known web crawlers" do
    post_signed({ From: "+15551234567", Body: "hello" },
                headers: { "User-Agent" => "Mozilla/5.0 (compatible; bingbot/2.0)" })

    assert_response :forbidden
    # Turned away before the signature is looked at.
    assert_not ErrorLog.exists?(error_type: "twilio-signature-invalid")
  end

  # =========================================================================
  # Message logging
  # =========================================================================

  test "inbound records both inbound and outbound messages" do
    # inbound message + outbound reply = 2 messages
    assert_difference("BroadcastMessage.count", 2) do
      post_signed({ From: "+15551234567", Body: "HELP" })
    end
  end

  # =========================================================================
  # Only what Twilio signed
  # =========================================================================

  test "an unsigned STOP is refused, changes nothing, and is logged without the text" do
    assert_no_difference("BroadcastMessage.count") do
      post infrastructure_sms_inbound_path, params: { From: "+15551234567", Body: "STOP" }
    end

    assert_response :forbidden
    assert_not @person.reload.sms_stopped?
    log = ErrorLog.find_by!(error_type: "twilio-signature-invalid")
    assert_equal({ "url" => TwilioSignatureConcern.address(infrastructure_sms_inbound_path), "signed" => false },
                 log.data)
  end

  test "a START signed with another token is refused" do
    @person.update_columns(sms_stopped: true)

    post_signed({ From: "+15551234567", Body: "START" }, token: "somebody-elses-token")

    assert_response :forbidden
    assert @person.reload.sms_stopped?
    assert_equal true, ErrorLog.find_by!(error_type: "twilio-signature-invalid").data["signed"]
  end

  test "a text changed after Twilio signed it is refused" do
    signed_for_help = signature({ From: "+15551234567", Body: "HELP" })

    post infrastructure_sms_inbound_path, params: { From: "+15551234567", Body: "STOP" },
                                          headers: { "X-Twilio-Signature" => signed_for_help }

    assert_response :forbidden
    assert_not @person.reload.sms_stopped?
  end

  test "every parameter posted is checked, including ones Twilio adds without notice" do
    post_signed({ From: "+15551234567", Body: "STOP", MessageSid: "SMdeadbeef", NumSegments: "1", AddedLater: "yes" })

    assert_response :success
    assert @person.reload.sms_stopped?
  end

  test "a text Twilio signed for Clubhouse 2's address is refused here" do
    post_signed({ From: "+15551234567", Body: "STOP" }, address: CLUBHOUSE2_ADDRESS)

    assert_response :forbidden
    assert_not @person.reload.sms_stopped?
  end

  test "a text signed for the address the request came in on is refused" do
    # http://www.example.com/...: the request's own address, not this server's.
    post_signed({ From: "+15551234567", Body: "STOP" }, address: infrastructure_sms_inbound_url)

    assert_response :forbidden
    assert_not @person.reload.sms_stopped?
  end

  test "a spoofed X-Forwarded-Host does not pass a text signed for that host" do
    post_signed({ From: "+15551234567", Body: "STOP" },
                address: "https://#{ANOTHER_HOST}#{infrastructure_sms_inbound_path}",
                headers: { "X-Forwarded-Host" => ANOTHER_HOST, "X-Forwarded-Proto" => "https" })

    assert_response :forbidden
    assert_not @person.reload.sms_stopped?
  end

  test "a text signed for this server passes whatever X-Forwarded-Host says" do
    post_signed({ From: "+15551234567", Body: "STOP" },
                headers: { "X-Forwarded-Host" => ANOTHER_HOST, "X-Forwarded-Proto" => "https" })

    assert_response :success
    assert @person.reload.sms_stopped?
  end

  test "an address URI cannot read is refused, not an error" do
    env = Rack::MockRequest.env_for(infrastructure_sms_inbound_path, method: "POST",
                                    params: { From: "+15551234567", Body: "STOP" })
    # Raw bytes, as any client can send them; the test client would refuse to.
    env["QUERY_STRING"] = "a=✓".b

    status, = Rails.application.call(env)

    assert_equal 403, status
    assert_not @person.reload.sms_stopped?
  end

  test "with no auth token set, every request is refused" do
    Setting.find(Setting::TWILIO_AUTH_TOKEN).destroy!

    post_signed({ From: "+15551234567", Body: "STOP" })

    assert_response :forbidden
    assert_not @person.reload.sms_stopped?
    assert ErrorLog.exists?(error_type: "twilio-auth-token-not-configured")
  end

  test "an empty auth token refuses a text signed with an empty key" do
    Setting.find(Setting::TWILIO_AUTH_TOKEN).update!(value: "")

    post_signed({ From: "+15551234567", Body: "STOP" }, token: "")

    assert_response :forbidden
    assert_not @person.reload.sms_stopped?
  end

  private

  # What Twilio sends as X-Twilio-Signature, by twilio-ruby's own validator:
  # signed with token over address and every parameter. This server's address
  # unless told otherwise.
  def signature(params, address: TwilioSignatureConcern.address(infrastructure_sms_inbound_path), token: AUTH_TOKEN)
    Twilio::Security::RequestValidator.new(token).build_signature_for(address, params)
  end

  def post_signed(params, headers: {}, **signing)
    post infrastructure_sms_inbound_path, params:, headers: { "X-Twilio-Signature" => signature(params, **signing), **headers }
  end
end
