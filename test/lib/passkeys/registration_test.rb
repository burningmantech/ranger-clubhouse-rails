# frozen_string_literal: true

require "test_helper"

# Adding a passkey with no request anywhere: a Hash is the session, and the
# library's stand-in is the browser and the device behind it.
class Passkeys::RegistrationTest < ActiveSupport::TestCase
  include PasskeyTestHelper

  setup do
    @person = person(:active_ranger)
    @person.password = "password"
    @person.save!(validate: false)
    @admin = person(:auditor_ranger)
    @admin.password = "admin-password"
    @admin.save!(validate: false)
    @session = {}
  end

  # --- start: everything refusable is refused before the device makes anything ---

  test "start hands the device its options, and leaves finish a note made out to the account" do
    existing = add_passkey_row(@person, nickname: "Already Here")

    options = start_own(nickname: "  My   Phone ")

    assert_equal PersonPasskey.user_handle(@person), options.dig("user", "id")
    assert_equal({ "residentKey" => "required", "userVerification" => "required" }, options["authenticatorSelection"])
    assert_equal [existing.external_id], options["excludeCredentials"].pluck("id")
    assert_equal({ "challenge" => options["challenge"], "nickname" => "My Phone", "person_id" => @person.id },
                 @session[Passkeys::Registration::SESSION_KEY].except("at"))
  end

  test "start refuses a nickname the passkey itself would refuse" do
    outcome = registration.start(nickname: "   ", current_password: "password")

    assert_equal "Give the passkey a nickname.", outcome.error
    assert_empty @session
  end

  test "start refuses an account that is already full" do
    fill_passkeys(@person)

    outcome = registration.start(nickname: "One Too Many", current_password: "password")

    assert_equal PersonPasskey::LIMIT_MESSAGE, outcome.error
    assert_empty @session
  end

  # For an Admin enrolling a key, the person's own password is not theirs to type.
  test "start asks for the password of whoever is at the keyboard" do
    outcome = enrollment.start(nickname: "HQ Key", current_password: "password")

    assert_equal Passkeys::Registration::WRONG_PASSWORD, outcome.error
    assert_empty @session
    start_enrollment
  end

  test "hardware_only steers the browser past the computer's own passkeys to a security key" do
    options = start_enrollment
    assert_equal "cross-platform", options.dig("authenticatorSelection", "authenticatorAttachment")
    assert_equal ["security-key"], options["hints"]

    options = start_own
    assert_nil options.dig("authenticatorSelection", "authenticatorAttachment")
    assert_nil options["hints"]
  end

  # --- finish ---

  test "finish keeps what the device made under the nickname noted at start, as the person's own" do
    credential = passkey_credential_for(start_own(nickname: "  My   Phone "))

    passkey = assert_accepted(registration.finish(credential))

    assert_equal @person, passkey.person
    assert_equal "My Phone", passkey.nickname
    assert_equal JSON.parse(credential)["id"], passkey.external_id
    assert_not passkey.added_by_admin?
    assert_empty @session
  end

  test "a security key an Admin enrolls goes on the person's account, as added by that Admin" do
    options = start_enrollment

    passkey = assert_accepted(enrollment.finish(passkey_credential_for(options, attachment: "cross-platform")))

    assert_equal @person, passkey.person
    assert_equal @admin, passkey.added_by
    assert_empty @admin.passkeys
  end

  # Single use: the first try takes the note, whatever becomes of that try.
  test "finish needs the note start left, and the note is good for one try" do
    assert_equal Passkeys::Registration::EXPIRED, registration.finish("{}").error

    options = start_own
    assert_equal Passkeys::Registration::UNVERIFIED, registration.finish("not json").error
    assert_equal Passkeys::Registration::EXPIRED, registration.finish(passkey_credential_for(options)).error
  end

  test "a device has five minutes to answer" do
    options = start_own
    travel(4.minutes) { assert_accepted(registration.finish(passkey_credential_for(options))) }

    options = start_own
    travel(6.minutes) do
      assert_equal Passkeys::Registration::EXPIRED, registration.finish(passkey_credential_for(options)).error
    end
  end

  # A second tab cannot finish it onto some other account.
  test "a note made out to one account cannot be finished on another" do
    options = start_own

    outcome = registration(person: @admin).finish(passkey_credential_for(options))

    assert_equal Passkeys::Registration::EXPIRED, outcome.error
  end

  test "a passkey made on another website is refused, and why is recorded" do
    ErrorLog.delete_all
    options = start_own
    elsewhere = WebAuthn::FakeClient.new("https://clubhouse.example.net")

    outcome = registration.finish(passkey_credential_for(options, device: elsewhere, rp_id: "www.example.com"))

    assert_equal Passkeys::Registration::UNVERIFIED, outcome.error
    entry = ErrorLog.where(error_type: "passkey-registration-refused").last
    assert_equal "WebAuthn::OriginVerificationError", entry.data["reason"]
    assert_equal @person.id, entry.data["person_id"]
    assert_equal @person.id, entry.data["actor_id"]
  end

  test "a passkey made without a fingerprint, face or PIN, or for some other challenge, is refused" do
    options = start_own
    assert_equal Passkeys::Registration::UNVERIFIED,
                 registration.finish(passkey_credential_for(options, user_verified: false)).error

    start_own # a new challenge in the note; options still holds the old one
    assert_equal Passkeys::Registration::UNVERIFIED, registration.finish(passkey_credential_for(options)).error
  end

  # The library raises whatever its parsers raise when handed bytes it cannot
  # read. None of it may get out.
  test "forged or mangled input is refused, not raised" do
    good = JSON.parse(passkey_credential_for(start_own))
    forgeries = [
      "", "not json", "[]", "{}", "42",
      good.except("response").to_json,
      good.merge("response" => good["response"].merge("attestationObject" => "!!!")).to_json,
      good.merge("response" => good["response"].merge("clientDataJSON" => Base64.urlsafe_encode64("nope", padding: false))).to_json
    ]

    forgeries.each do |forgery|
      start_own
      assert_equal Passkeys::Registration::UNVERIFIED, registration.finish(forgery).error, "#{forgery.first(40)} was not refused"
    end
    assert_empty @person.passkeys
  end

  # --- the hardware rule, for a key an Admin enrolls ---

  test "hardware_only refuses a passkey that can be copied between devices, and records it" do
    ErrorLog.delete_all
    options = start_enrollment

    assert_no_difference -> { PersonPasskey.count } do
      outcome = enrollment.finish(passkey_credential_for(options, attachment: "cross-platform",
                                                                  backup_eligibility: true, backup_state: true))
      assert_equal Passkeys::Registration::NOT_HARDWARE, outcome.error
    end

    entry = ErrorLog.where(error_type: "passkey-enrollment-not-hardware").last
    assert_equal @person.id, entry.data["person_id"]
    assert_equal @admin.id, entry.data["actor_id"]
  end

  test "hardware_only refuses a passkey the browser says lives in the computer itself" do
    options = start_enrollment

    outcome = enrollment.finish(passkey_credential_for(options, attachment: "platform"))

    assert_equal Passkeys::Registration::NOT_HARDWARE, outcome.error
  end

  # A person's own phone and password manager are exactly what their own page
  # is for.
  test "a person's own passkey may be one that syncs between their devices" do
    options = start_own

    assert_accepted(registration.finish(passkey_credential_for(options, backup_eligibility: true, backup_state: true)))
  end

  # --- saving ---

  test "a passkey already on another account is refused" do
    credential = passkey_credential_for(start_own)
    add_passkey_row(@admin, nickname: "Got There First", external_id: JSON.parse(credential)["id"])

    assert_equal Passkeys::Registration::DUPLICATE, registration.finish(credential).error
  end

  # Another tab can fill the account between start and finish.
  test "the passkey's own rules have the last word when it is saved" do
    options = start_own
    fill_passkeys(@person)

    assert_equal PersonPasskey::LIMIT_MESSAGE, registration.finish(passkey_credential_for(options)).error
  end

  private

  def registration(person: @person, actor: person, hardware_only: false)
    Passkeys::Registration.new(person: person, actor: actor, hardware_only: hardware_only,
                               session: @session, relying_party: passkey_relying_party)
  end

  # An Admin enrolling a security key on the person's account.
  def enrollment
    registration(actor: @admin, hardware_only: true)
  end

  def start_own(nickname: "My Phone")
    passkey_options_from(registration.start(nickname: nickname, current_password: "password"))
  end

  def start_enrollment
    passkey_options_from(enrollment.start(nickname: "HQ Key", current_password: "admin-password"))
  end
end
