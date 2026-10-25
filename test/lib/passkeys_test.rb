# frozen_string_literal: true

require "test_helper"

# The address passkeys belong to, and when passkeys are offered at all.
class PasskeysTest < ActiveSupport::TestCase
  include PasskeyTestHelper
  include SsoTestHelper

  ORIGIN = "https://clubhouse.example.org"

  # --- origin ---

  test "the address comes from the environment" do
    with_passkey_origin(ORIGIN) do
      assert_equal ORIGIN, Passkeys.origin(request_at("localhost:3000"))
    end
  end

  test "space around the address is not part of it" do
    with_passkey_origin("  #{ORIGIN}\n") do
      assert_equal ORIGIN, Passkeys.origin(request_at("localhost:3000"))
    end
  end

  test "with nothing set, a development machine answers for itself" do
    with_passkey_origin(nil) do
      assert_equal "http://localhost:3210", Passkeys.origin(request_at("localhost:3210"))
      assert_equal "http://www.example.com", Passkeys.origin(request_at("www.example.com"))
    end
  end

  # No browser makes a passkey for an IP address, so a button there could only fail.
  test "with nothing set, a development machine reached by IP address offers nothing" do
    with_passkey_origin(nil) do
      assert_nil Passkeys.origin(request_at("127.0.0.1:3000"))
      assert_nil Passkeys.origin(request_at("[::1]:3000"))
      assert_not Passkeys.enabled?(request_at("127.0.0.1:3000"))
    end
  end

  test "with nothing set, production offers nothing" do
    with_passkey_origin(nil) do
      with_rails_env("production") do
        assert_nil Passkeys.origin(request_at("clubhouse.example.org"))
        assert_not Passkeys.enabled?(request_at("clubhouse.example.org"))
      end
    end
  end

  test "production takes the address from the environment, never from the request" do
    with_passkey_origin(ORIGIN) do
      with_rails_env("production") do
        assert_equal ORIGIN, Passkeys.origin(request_at("evil.example.net"))
      end
    end
  end

  # --- enabled? ---

  test "passkeys are on when there is an address and the password form is on" do
    with_passkey_origin(ORIGIN) do
      with_sso_mode(nil) { assert Passkeys.enabled?(request_at("localhost:3000")) }
      with_sso_mode(Sso::SERVER) { assert Passkeys.enabled?(request_at("localhost:3000")) }
    end
  end

  # --- relying_party ---

  test "the relying party is the address, its host name, and the Clubhouse's name" do
    with_passkey_origin("https://clubhouse.example.org:8443") do
      relying_party = Passkeys.relying_party(request_at("localhost:3000"))

      assert_equal ["https://clubhouse.example.org:8443"], relying_party.allowed_origins
      assert_equal "clubhouse.example.org", relying_party.id
      assert_equal "Ranger Clubhouse", relying_party.name
    end
  end

  test "asking for the relying party where passkeys are off says so" do
    with_passkey_origin(nil) do
      with_rails_env("production") do
        error = assert_raises(Passkeys::ConfigurationError) do
          Passkeys.relying_party(request_at("clubhouse.example.org"))
        end
        assert_includes error.message, Passkeys::ORIGIN_VAR
      end
    end
  end

  # The whole point of naming the address: a passkey presented from any other
  # website is refused, however genuine the device behind it.
  test "a passkey made at this address is accepted, and one made anywhere else is not" do
    with_passkey_origin(ORIGIN) do
      relying_party = Passkeys.relying_party(request_at("localhost:3000"))
      options = relying_party.options_for_registration(
        user: { id: PersonPasskey.user_handle(person(:active_ranger)), name: "ranger@example.com" }
      )

      here = WebAuthn::FakeClient.new(ORIGIN).create(challenge: options.challenge, user_verified: true)
      credential = relying_party.verify_registration(here, options.challenge, user_verification: true)
      assert_predicate credential.id, :present?
      assert_predicate credential.public_key, :present?

      elsewhere = WebAuthn::FakeClient.new("https://clubhouse.example.net")
                                      .create(challenge: options.challenge, rp_id: "clubhouse.example.org", user_verified: true)
      assert_raises(WebAuthn::OriginVerificationError) do
        relying_party.verify_registration(elsewhere, options.challenge, user_verification: true)
      end
    end
  end

  # --- validate! ---

  test "nothing set, or an address a passkey can belong to, boots" do
    [nil, "", ORIGIN, "https://clubhouse.example.org:8443", "http://localhost:3000", "http://localhost"].each do |origin|
      with_passkey_origin(origin) do
        assert_nothing_raised { Passkeys.validate! }
      end
    end
  end

  # Each of these would fail every sign-in with nothing on the page to say why:
  # the browser compares the address as text, and will not make a passkey for
  # plain http or for an IP address.
  test "an address no passkey could belong to stops the boot and says what is wanted" do
    [
      "http://clubhouse.example.org",
      "https://clubhouse.example.org/",
      "https://clubhouse.example.org/me",
      "https://clubhouse.example.org?x=1",
      "https://clubhouse.example.org:443",
      "https://Clubhouse.Example.org",
      "https://user@clubhouse.example.org",
      "https://10.0.0.5",
      "http://127.0.0.1:3000",
      "clubhouse.example.org",
      "not an address"
    ].each do |origin|
      with_passkey_origin(origin) do
        error = assert_raises(Passkeys::ConfigurationError, "#{origin.inspect} should not boot") { Passkeys.validate! }
        assert_includes error.message, Passkeys::ORIGIN_VAR
        assert_includes error.message, origin.inspect
      end
    end
  end

  private

  def request_at(host)
    ActionDispatch::TestRequest.create("HTTP_HOST" => host)
  end

  # Rails.env is process-wide, and the suite runs one test at a time.
  def with_rails_env(name)
    saved = Rails.env
    Rails.env = name
    yield
  ensure
    Rails.env = saved
  end
end
