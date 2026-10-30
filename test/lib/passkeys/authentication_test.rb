# frozen_string_literal: true

require "test_helper"

# Signing in with a passkey with no request anywhere: a Hash is the session,
# and the library's stand-in is the browser and the device behind it.
class Passkeys::AuthenticationTest < ActiveSupport::TestCase
  include PasskeyTestHelper

  setup do
    @person = person(:active_ranger)
    @passkey = register_passkey_for(@person)
    @session = {}
  end

  test "start names no account, asks for the fingerprint, face or PIN, and leaves finish a note" do
    options = start

    assert_empty options["allowCredentials"]
    assert_equal "required", options["userVerification"]
    assert_equal options["challenge"], @session[Passkeys::Authentication::SESSION_KEY]["challenge"]
  end

  test "finish says whose passkey it was, and records its use" do
    options = start

    freeze_time do
      passkey = assert_accepted(authentication.finish(passkey_assertion_for(options, sign_count: 7)))

      assert_equal @person, passkey.person
      assert_equal 7, @passkey.reload.sign_count
      assert_equal Time.current, @passkey.last_used_at
    end
    assert_empty @session
  end

  # Single use: the first try takes the note, whatever becomes of that try.
  test "finish needs the note start left, and the note is good for one try" do
    assert_equal Passkeys::Authentication::EXPIRED, authentication.finish("{}").error

    options = start
    assert_equal Passkeys::Authentication::UNRECOGNIZED, authentication.finish("not json").error
    assert_equal Passkeys::Authentication::EXPIRED, authentication.finish(passkey_assertion_for(options)).error
  end

  test "a device has five minutes to answer" do
    options = start
    travel(4.minutes) { assert_accepted(authentication.finish(passkey_assertion_for(options))) }

    options = start
    travel(6.minutes) do
      assert_equal Passkeys::Authentication::EXPIRED, authentication.finish(passkey_assertion_for(options)).error
    end
  end

  # The one sentence for every failure: from outside, an unknown passkey and a
  # failed one look the same. (A passkey whose account is gone cannot exist:
  # person_passkey.person_id is a foreign key, and Person destroys its passkeys.)
  test "a passkey that is gone is refused" do
    @passkey.delete
    assert_equal Passkeys::Authentication::UNRECOGNIZED, authentication.finish(passkey_assertion_for(start)).error
  end

  # The library raises whatever its parsers raise when handed bytes it cannot
  # read. None of it may get out.
  test "forged or mangled input is refused, not raised" do
    good = JSON.parse(passkey_assertion_for(start))
    forgeries = [
      "", "not json", "[]", "{}", "42",
      good.merge("id" => ["x"]).to_json,
      good.except("response").to_json,
      good.merge("response" => good["response"].merge("signature" => "AAAA")).to_json,
      good.merge("response" => good["response"].merge("authenticatorData" => "!!!")).to_json
    ]

    forgeries.each do |forgery|
      start
      assert_equal Passkeys::Authentication::UNRECOGNIZED, authentication.finish(forgery).error, "#{forgery.first(40)} was not refused"
    end
    assert_nil @passkey.reload.last_used_at
  end

  test "a passkey answering from another website is refused, and why is recorded" do
    ErrorLog.delete_all
    key = WebAuthn::FakeAuthenticator.new
    passkey = register_passkey_for(@person, device: WebAuthn::FakeClient.new(PasskeyTestHelper::REQUEST_ORIGIN, authenticator: key))
    elsewhere = WebAuthn::FakeClient.new("https://clubhouse.example.net", authenticator: key)

    outcome = authentication.finish(passkey_assertion_for(start, device: elsewhere, rp_id: "www.example.com"))

    assert_equal Passkeys::Authentication::UNRECOGNIZED, outcome.error
    entry = ErrorLog.where(error_type: "passkey-sign-in-refused").last
    assert_equal "WebAuthn::OriginVerificationError", entry.data["reason"]
    assert_equal passkey.id, entry.data["passkey_id"]
    assert_equal @person.id, entry.data["person_id"]
  end

  test "a passkey used without the fingerprint, face or PIN is refused" do
    outcome = authentication.finish(passkey_assertion_for(start, user_verified: false))

    assert_equal Passkeys::Authentication::UNRECOGNIZED, outcome.error
  end

  # The one failure that can mean a copied security key.
  test "a counter that went backwards is refused and recorded under its own name" do
    ErrorLog.delete_all
    @passkey.update_columns(sign_count: 100)

    outcome = authentication.finish(passkey_assertion_for(start, sign_count: 5))

    assert_equal Passkeys::Authentication::UNRECOGNIZED, outcome.error
    assert_equal 100, @passkey.reload.sign_count
    assert_equal @passkey.id, ErrorLog.where(error_type: "passkey-sign-count-regression").last.data["passkey_id"]
  end

  # Not every device names the account it filed the passkey under. One that
  # does must name the account the passkey is on.
  test "a device that names an account must name the passkey's own" do
    assert_accepted(authentication.finish(passkey_assertion_for(start, user_handle: @person.id.to_s)))

    someone_else = person(:auditor_ranger)
    outcome = authentication.finish(passkey_assertion_for(start, user_handle: someone_else.id.to_s))
    assert_equal Passkeys::Authentication::UNRECOGNIZED, outcome.error
  end

  private

  def authentication
    Passkeys::Authentication.new(session: @session, relying_party: passkey_relying_party)
  end

  def start
    passkey_options_from(authentication.start)
  end
end
