# frozen_string_literal: true

require "application_system_test_case"

# A search can fail three ways: no connection, a server error, or a sign-in
# that has expired. The dialog says which, in place of the autocomplete's own
# one-line message, without leaving the page. Chrome's own offline switch
# (DevTools Protocol) stands in for a lost connection.
class SearchBarFailureTest < ApplicationSystemTestCase
  include TimesheetAdminTestHelper

  DIALOG = "[data-search-bar-target='dialog'][open]"
  INPUT = "[data-search-bar-target='input']"
  OFFLINE = "#{DIALOG} [data-kind='offline']".freeze
  FAILED = "#{DIALOG} [data-kind='failed']".freeze
  EXPIRED = "#{DIALOG} [data-kind='expired']".freeze

  setup do
    @person = person(:active_ranger)
    ensure_role(Role::EVENT_MANAGEMENT, "Event Management")
    grant_role(@person, Role::EVENT_MANAGEMENT)
    sign_in(@person)
    visit me_root_path
    open_search
  end

  # One browser serves the whole run: leave it online, with events off
  teardown do
    offline(false)
    page.driver.browser.execute_cdp("Network.disable")
  end

  test "a search that cannot reach the server says so, and Try Again runs it" do
    offline(true)
    find(INPUT).fill_in with: "TestRanger"

    assert_selector OFFLINE, text: "Can't Reach the Clubhouse", wait: 5
    assert_no_selector "#{DIALOG} .ac-error"
    assert_selector "#{INPUT}:focus"

    offline(false)
    within(OFFLINE) { click_on "Try Again" }

    assert_selector "#{DIALOG} [role='option']", text: "TestRanger", wait: 5
    assert_selector OFFLINE, visible: :hidden
    # The button went with its callout; the box has the focus, so the
    # arrow keys reach the results
    assert_selector "#{INPUT}:focus"
  end

  test "Try Again runs the same search, filter chip and all" do
    find(INPUT).fill_in with: "Test"
    auditor = "#{DIALOG} .ac-filter-chip[data-autocomplete-filter-value='auditor']"
    assert_selector auditor, wait: 5

    offline(true)
    find(auditor).click
    assert_selector OFFLINE, wait: 5

    offline(false)
    within(OFFLINE) { click_on "Try Again" }

    assert_selector "#{DIALOG} .ac-filter-chip-active[data-autocomplete-filter-value='auditor']", wait: 5
  end

  test "a failure callout goes when the search box changes" do
    offline(true)
    find(INPUT).fill_in with: "TestRanger"
    assert_selector OFFLINE, wait: 5

    find(INPUT).send_keys(*([:backspace] * 10))

    assert_selector OFFLINE, visible: :hidden, wait: 2
    assert_equal "", find(INPUT).value
  end

  # The warning sits in the search's own "Searching..." row, under the box,
  # with nothing to press that would call the search off
  test "a search still out after ten seconds says so in its Searching row" do
    page.execute_script(<<~JS)
      window.fetch = (input, init = {}) => new Promise((resolve, reject) => {
        init.signal?.addEventListener("abort", () => reject(init.signal.reason))
      })
      const realSetTimeout = window.setTimeout
      window.setTimeout = (fn, ms, ...args) => realSetTimeout(fn, ms >= 10000 ? 100 : ms, ...args)
    JS
    find(INPUT).fill_in with: "TestRanger"

    assert_selector "#{DIALOG} .ac-searching", text: "Still searching. Your connection may be slow.", wait: 5
  end

  test "a search after the sign-in expired says so and stays on the page" do
    sign_out
    find(INPUT).fill_in with: "TestRanger"

    assert_selector EXPIRED, text: "You've Been Signed Out", wait: 5
    assert_equal me_root_path, URI(current_url).path

    click_on "Sign In Again"

    assert_current_path root_path, wait: 5
  end

  test "a server error says so, and opening the search again runs it again" do
    original = AutocompleteController.instance_method(:search)
    AutocompleteController.define_method(:search) { head :internal_server_error }
    find(INPUT).fill_in with: "TestRanger"

    assert_selector FAILED, text: "The Clubhouse Had a Problem", wait: 5

    AutocompleteController.define_method(:search, original)
    within(FAILED) { click_on "Close Search" }
    assert_no_selector DIALOG, wait: 2
    open_search

    assert_selector "#{DIALOG} [role='option']", text: "TestRanger", wait: 5
    assert_selector FAILED, visible: :hidden
  ensure
    AutocompleteController.define_method(:search, original)
  end

  private

    def open_search
      page.execute_script(<<~JS)
        document.dispatchEvent(new KeyboardEvent("keydown",
          { key: "k", ctrlKey: true, bubbles: true, cancelable: true }))
      JS
      assert_selector DIALOG, wait: 2
    end

    # Network.enable first: without it the emulation silently does nothing
    def offline(state)
      browser = page.driver.browser
      browser.execute_cdp("Network.enable")
      browser.execute_cdp("Network.emulateNetworkConditions",
                          offline: state, latency: 0, downloadThroughput: -1, uploadThroughput: -1)
    end
end
