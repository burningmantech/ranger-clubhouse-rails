# frozen_string_literal: true

require "application_system_test_case"

# Capybara empties the browser after every system test, so that none starts signed in as the last one's
# person or with what it left in storage. Every test leans on that and no other test checks it: when
# Chrome 158 began to refuse the call Capybara makes for it, each one passed its assertions and then
# errored in teardown (test/support/chrome_reset_without_wildcard_origin.rb).
class BrowserResetTest < ApplicationSystemTestCase
  # The server's own address, and the name the passkey tests reach it by. To a browser they are two sites,
  # each with its own cookies and storage.
  HOSTS = %w[127.0.0.1 localhost].freeze

  test "a reset signs the browser out and empties its storage on each host a test visited" do
    person = person(:active_ranger)

    on_each_host do
      sign_in(person)
      visit me_root_path
      assert_selector "h1", text: "Welcome Ranger #{person.callsign}"
      page.execute_script("localStorage.setItem('browser-reset-test', 'left behind')")
      page.execute_script("sessionStorage.setItem('browser-reset-test', 'left behind')")
    end

    Capybara.reset_sessions!

    on_each_host do
      visit me_root_path
      assert_selector "h1.login-title"
      assert_nil page.evaluate_script("localStorage.getItem('browser-reset-test')")
      assert_nil page.evaluate_script("sessionStorage.getItem('browser-reset-test')")
    end
  end

  private

  def on_each_host
    saved_app_host = Capybara.app_host
    HOSTS.each do |host|
      Capybara.app_host = "http://#{host}:#{Capybara.current_session.server.port}"
      yield
    end
  ensure
    Capybara.app_host = saved_app_host
  end
end
