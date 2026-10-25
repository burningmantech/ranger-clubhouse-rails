# frozen_string_literal: true

# The WebAuthn library's stand-in for a browser and the device behind it. It
# ships with the gem but is not loaded with it.
require "webauthn/fake_client"

# Passkeys in tests: the address they belong to, and a stand-in for the
# browser and the device behind it.
#
# The address is read from the environment on every call and nothing else in
# the test process sets it, so a test sets what it needs and the teardown here
# clears it. With nothing set, a request answers for itself -- and an
# integration test's requests arrive at http://www.example.com.
module PasskeyTestHelper
  extend ActiveSupport::Concern

  REQUEST_ORIGIN = "http://www.example.com"

  included do
    teardown { ENV.delete(Passkeys::ORIGIN_VAR) }
  end

  # One device, kept for the whole test: what it registers it can sign in with.
  def passkey_device
    @passkey_device ||= WebAuthn::FakeClient.new(REQUEST_ORIGIN)
  end

  # The app's own relying party for a request at REQUEST_ORIGIN, so a test with
  # no request checks passkeys exactly as the app does.
  def passkey_relying_party
    Passkeys.relying_party(ActionDispatch::TestRequest.create("HTTP_HOST" => URI.parse(REQUEST_ORIGIN).host))
  end

  # What a ceremony's Outcome carries, failing the test with the ceremony's
  # own sentence when it was refused.
  def assert_accepted(outcome)
    assert_predicate outcome, :ok?, outcome.error
    outcome.value
  end

  # What the page's script is handed: a ceremony's options, as the controller
  # renders them.
  def passkey_options_from(outcome)
    JSON.parse(assert_accepted(outcome).to_json)
  end

  # What the page's script would put in the hidden field once the device has
  # made a passkey for these options. Keywords go to the device: user_verified:
  # false is someone who skipped their fingerprint, backup_eligibility: true a
  # passkey that syncs between devices.
  #
  # attachment: is what the browser says the passkey came from. The library's
  # stand-in always says "platform" -- the computer itself -- so a test about
  # a plugged-in security key says "cross-platform" here.
  def passkey_credential_for(options, device: passkey_device, user_verified: true, attachment: nil, **device_options)
    credential = device.create(challenge: options.fetch("challenge"), user_verified: user_verified, **device_options)
    credential["authenticatorAttachment"] = attachment if attachment
    credential.to_json
  end

  # A passkey already on an account, made by a device the test can then sign in
  # with. Straight to the table, the way it would stand after Add Passkey.
  def register_passkey_for(person, nickname: "Test Key", device: passkey_device, **attributes)
    relying_party = passkey_relying_party
    options = relying_party.options_for_registration(user: { id: PersonPasskey.user_handle(person), name: person.email })
    credential = relying_party.verify_registration(device.create(challenge: options.challenge, user_verified: true),
                                                   options.challenge, user_verification: true)
    person.passkeys.create!({ nickname: nickname, external_id: credential.id, public_key: credential.public_key,
                              sign_count: credential.sign_count }.merge(attributes))
  end

  # A passkey row with no device behind it, so nothing can sign in with it: for
  # lists, limits and ids, where the key itself is never checked.
  def add_passkey_row(person, nickname:, **attributes)
    PersonPasskey.create!({ person: person, nickname: nickname,
                            external_id: SecureRandom.urlsafe_base64(16),
                            public_key: SecureRandom.urlsafe_base64(77) }.merge(attributes))
  end

  # Every passkey an account may hold, so the next one is refused.
  def fill_passkeys(person)
    PersonPasskey::MAX_PER_PERSON.times { |n| add_passkey_row(person, nickname: "Key #{n}") }
  end

  # What the page's script would put in the hidden field once the device has
  # answered a sign-in challenge. Keywords go to the device: sign_count: is the
  # counter it presents, user_handle: the account it says the passkey is filed
  # under (raw, as the device holds it).
  def passkey_assertion_for(options, device: passkey_device, user_verified: true, **device_options)
    device.get(challenge: options.fetch("challenge"), user_verified: user_verified, **device_options).to_json
  end

  # The address for one block, then whatever the test had before it. nil
  # leaves it unset, which is how every development machine runs.
  def with_passkey_origin(origin)
    saved = ENV.fetch(Passkeys::ORIGIN_VAR, nil)
    origin.nil? ? ENV.delete(Passkeys::ORIGIN_VAR) : ENV[Passkeys::ORIGIN_VAR] = origin
    yield
  ensure
    saved.nil? ? ENV.delete(Passkeys::ORIGIN_VAR) : ENV[Passkeys::ORIGIN_VAR] = saved
  end

  # Passkeys off for the rest of an integration test, the way a production
  # machine with no address set has them: no address, and a request at an IP
  # address cannot answer for itself.
  def switch_passkeys_off
    ENV.delete(Passkeys::ORIGIN_VAR)
    host! "127.0.0.1"
  end
end
