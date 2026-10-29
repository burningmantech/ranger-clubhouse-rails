# frozen_string_literal: true

require "application_system_test_case"

# The navbar's "Hello <callsign>" menu is a native <details>, which only its own
# summary closes. application.js closes it from a link inside it or a click
# outside it, so the copy of the page Turbo caches on the way out -- the one
# Back shows -- is never taken with the menu open.
class AccountMenuTest < ApplicationSystemTestCase
  setup do
    @person = person(:active_ranger)
    sign_in(@person)
    visit me_root_path
    assert_selector "h1", text: "Welcome Ranger #{@person.callsign}"
  end

  test "a link in the account menu closes it, so Back does not bring the page back with it open" do
    open_account_menu
    click_link "My Profile"
    assert_no_selector "h1", text: "Welcome Ranger #{@person.callsign}"

    go_back
    assert_selector "h1", text: "Welcome Ranger #{@person.callsign}"
    assert_no_selector "details.account-menu[open]"
  end

  test "a click outside the account menu closes it" do
    open_account_menu
    find("h1", text: "Welcome Ranger #{@person.callsign}").click
    assert_no_selector "details.account-menu[open]"
  end

  private

  def open_account_menu
    find("summary", text: "Hello #{@person.callsign}").click
    assert_selector "details.account-menu[open]"
  end
end
