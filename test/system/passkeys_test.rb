# frozen_string_literal: true

require "application_system_test_case"

# The one place the page's script, the browser's passkey machinery and the
# Clubhouse all meet. Chrome's virtual authenticator stands in for the phone,
# laptop or security key, and answers its prompts on its own.
class PasskeysSystemTest < ApplicationSystemTestCase
  include TimesheetAdminTestHelper

  setup do
    # Capybara serves at http://127.0.0.1:<port>, and no browser will make a
    # passkey for an IP address: it throws SecurityError before the Clubhouse
    # is asked anything. The same server answers to its name.
    @saved_app_host = Capybara.app_host
    Capybara.app_host = "http://localhost:#{Capybara.current_session.server.port}"

    @person = person(:active_ranger)
    @person.password = "password"
    @person.save!(validate: false)
    sign_in(@person)

    @authenticator = page.driver.browser.add_virtual_authenticator(
      Selenium::WebDriver::VirtualAuthenticatorOptions.new(
        protocol: :ctap2, transport: :internal,
        resident_key: true, user_verification: true, user_verified: true
      )
    )
  end

  teardown do
    @authenticator&.remove!
    Capybara.app_host = @saved_app_host
  end

  test "adding a passkey, then removing it" do
    visit me_profile_passkeys_path
    assert_text "No passkeys yet."

    add_passkey "Test Laptop"

    assert_selector "th[scope=row]", text: "Test Laptop"
    assert_equal 1, @authenticator.credentials.size, "the device should hold exactly the passkey it was asked for"

    passkey = @person.passkeys.sole
    assert_equal "Test Laptop", passkey.nickname
    assert_not passkey.added_by_admin?

    click_link "Delete"
    assert_selector "dialog[open]", text: "Delete Test Laptop?"
    accept_confirm_dialog

    assert_text "Test Laptop can no longer sign you in."
    assert_text "No passkeys yet."
    assert_equal 0, @person.passkeys.count
  end

  test "signing in with a passkey, no email address asked for" do
    add_passkey "Test Laptop"
    sign_out

    visit root_path
    click_button "Sign In with a Passkey"

    assert_current_path me_root_path
    passkey = @person.passkeys.sole
    assert_not_nil passkey.last_used_at
    assert_equal passkey.id, ActionLog.where(event: "auth-login", person_id: @person.id).last.data["passkey_id"]
  end

  # The device still holds a passkey the Clubhouse has let go of: removed by
  # the person on another computer, or by an Admin.
  test "a passkey the Clubhouse no longer holds lands back on the sign-in page with the reason" do
    add_passkey "Test Laptop"
    sign_out
    @person.passkeys.destroy_all

    visit root_path
    click_button "Sign In with a Passkey"

    # The address first: see add_passkey.
    assert_current_path passkey_sign_in_path
    assert_text "The Clubhouse doesn't recognize that passkey."
    assert_field "Email Address"
  end

  # The key the Tech Team hands over. A second authenticator stands in for it:
  # one that plugs in, where the first is the computer itself. The page asks the
  # browser for a plugged-in key, so the computer's own must be passed over.
  test "an Admin enrolls a security key for someone, who then signs in with it" do
    admin = person(:auditor_ranger)
    admin.password = "admin-password"
    admin.save!(validate: false)
    ensure_role(Role::ADMIN, "Admin")
    grant_role(admin, Role::ADMIN)
    key = page.driver.browser.add_virtual_authenticator(
      Selenium::WebDriver::VirtualAuthenticatorOptions.new(
        protocol: :ctap2, transport: :usb,
        resident_key: true, user_verification: true, user_verified: true
      )
    )
    sign_out
    sign_in(admin)

    visit person_passkeys_path(@person)
    click_link "Add Security Key"
    fill_in "Nickname", with: "HQ Key 7"
    fill_in "Your Current Password", with: "admin-password"
    click_button "Add Security Key"

    # The address first: see add_passkey.
    assert_current_path person_passkeys_path(@person)
    assert_text "HQ Key 7 can now sign in as #{@person.callsign}"
    assert_equal 1, key.credentials.size
    assert_empty @authenticator.credentials, "the computer's own authenticator should have been passed over"

    passkey = @person.passkeys.sole
    assert_equal admin, passkey.added_by
    assert_equal 0, admin.passkeys.count

    sign_out
    visit root_path
    click_button "Sign In with a Passkey"

    assert_current_path me_root_path
    assert_equal passkey.id, ActionLog.where(event: "auth-login", person_id: @person.id).last.data["passkey_id"]
  ensure
    key&.remove!
  end

  test "the wrong password is refused before the device is asked for anything" do
    visit new_me_profile_passkey_path
    fill_in "Nickname", with: "Test Laptop"
    fill_in "Current Password", with: "not my password"
    click_button "Add Passkey"

    assert_text "That is not your current password."
    assert_button "Add Passkey", disabled: false
    assert_empty @authenticator.credentials
    assert_equal 0, @person.passkeys.count
  end

  private

  def add_passkey(nickname)
    visit new_me_profile_passkey_path
    fill_in "Nickname", with: nickname
    fill_in "Current Password", with: "password"
    click_button "Add Passkey"

    # The script sends the form as a full page load once the device has
    # answered. Wait on the address, which asks nothing of the page, before
    # reading the page: Chrome answers a read that lands mid-navigation with
    # "Node with given id does not belong to the document", which Capybara
    # does not know to retry.
    assert_current_path me_profile_passkeys_path
    assert_text "#{nickname} can now sign you in."
  end
end
