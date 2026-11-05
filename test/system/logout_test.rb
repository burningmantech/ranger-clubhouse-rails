# frozen_string_literal: true

require "application_system_test_case"

class LogoutTest < ApplicationSystemTestCase
  test "signing out in one window takes the browser's other windows to the sign-in page" do
    person = person(:active_ranger)
    sign_in(person)
    other = open_new_window
    within_window(other) do
      visit me_root_path
      assert_selector "h1", text: "Welcome Ranger #{person.callsign}"
    end

    visit me_root_path
    find("summary", text: "Hello #{person.callsign}").click
    within("details.account-menu[open]") { click_link "Logout" }
    accept_confirm_dialog
    assert_selector "h1.login-title"

    within_window(other) { assert_selector "h1.login-title" }
  end
end
