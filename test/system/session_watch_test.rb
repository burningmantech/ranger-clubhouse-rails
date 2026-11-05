# frozen_string_literal: true

require "application_system_test_case"

# session_watch_controller.js beyond the plain sign-out in another window
# (logout_test.rb). Each test ends the page's sign-in from here, as a sign-out
# elsewhere or a revoke would: Session's after_destroy_commit closes its socket
# for good.
class SessionWatchTest < ApplicationSystemTestCase
  setup do
    @person = person(:active_ranger)
    sign_in(@person)
    visit me_root_path
    assert_selector "h1", text: "Welcome Ranger #{@person.callsign}"
  end

  # The window whose own request ended the sign-in hears the close too. Leaving
  # then would cancel that request's own way to the sign-in page, and with it a
  # locked account's reason.
  test "a window that is mid-navigation lets that navigation land and only then leaves" do
    page.execute_script(<<~JS)
      window.visits = []
      document.addEventListener("turbo:before-visit", (event) => window.visits.push(event.detail.url))
      document.documentElement.setAttribute("aria-busy", "true")
    JS

    @person.sessions.sole.destroy

    # The stream source hears the close in the same turn as the watcher.
    assert_no_selector "turbo-cable-stream-source[connected]", visible: :all
    assert_empty page.evaluate_script("window.visits")

    page.execute_script("document.documentElement.removeAttribute('aria-busy')")
    assert_selector "h1.login-title"
  end

  # A real unsaved-changes form, the guard HQ › Shift extends: asking here would
  # leave a dead page on screen with nothing to save it to.
  test "unsaved changes do not hold a page whose sign-in has ended" do
    page.execute_script(<<~JS)
      document.querySelector("main").insertAdjacentHTML("beforeend",
        '<form id="draft-form" data-controller="unsaved-changes"><input id="draft" name="draft"></form>')
    JS
    wait_for_controller "unsaved-changes", "#draft-form"
    fill_in "draft", with: "Half a message"

    @person.sessions.sole.destroy

    assert_selector "h1.login-title"
  end

  # Someone else signed in on this browser while the page's socket was down: it
  # comes back under their cookie, and the page drawn for the earlier sign-in
  # must not stay up beside it.
  test "a page whose socket comes back under a newer sign-in goes to that sign-in's dashboard" do
    newer = person(:ranger_with_custom_gender)
    newer.update_column(:on_boarded_at, Time.current)
    use_session_cookie(newer.sessions.create!(session_id: SecureRandom.hex(32)))

    page.execute_script(<<~JS)
      import("@hotwired/turbo-rails").then(({cable}) => cable.getConsumer()).then((consumer) => consumer.connection.reopen())
    JS

    assert_selector "h1", text: newer.callsign
  end

  test "Back from the sign-in page brings back none of the signed-out person's pages" do
    find("summary", text: "Hello #{@person.callsign}").click
    within("details.account-menu[open]") { click_link "My Profile" }
    assert_current_path me_profile_path
    # The cookie goes without the sign-in ending, so no close arrives: the next
    # visit is what finds the browser signed out, and Turbo caches this page on
    # the way.
    sign_out
    find("a.sidebar-nav-item[href='#{me_root_path}']").click
    assert_selector "h1.login-title"

    go_back

    assert_selector "h1.login-title"
  end
end

# Pages accept a sign-in the cable refuses: AuthenticationTestHelper's parked
# session answers every page request, and the browser has no cookie for its
# socket. A watcher that left on that refusal would go to /, be sent on to /me,
# and go round for good.
class SessionWatchRefusedSocketTest < ApplicationSystemTestCase
  include AuthenticationTestHelper

  test "a socket refused before it was ever accepted leaves the page where it is" do
    browser = page.driver.browser
    recorder = browser.execute_cdp("Page.addScriptToEvaluateOnNewDocument", source: <<~JS)
      window.visits = []
      document.addEventListener("turbo:before-visit", (event) => window.visits.push(event.detail.url))
    JS
    person = person(:active_ranger)
    person.update_column(:on_boarded_at, Time.current)
    sign_in_as(person)

    # Capybara's own visit: the test's waits for every stream source to
    # connect, and this one is refused.
    page.visit me_root_path
    assert_selector "h1", text: "Welcome Ranger #{person.callsign}"
    # Until the watcher has subscribed and the socket is closed for good.
    assert_eventually { page.evaluate_async_script(<<~JS) }
      const done = arguments[arguments.length - 1]
      import("@hotwired/turbo-rails").then(({cable}) => cable.getConsumer()).then((consumer) => {
        const watching = consumer.subscriptions.subscriptions.some((s) => JSON.parse(s.identifier).channel === "SessionChannel")
        done(watching && !consumer.connection.isActive())
      })
    JS

    assert_empty page.evaluate_script("window.visits")
  ensure
    browser&.execute_cdp("Page.removeScriptToEvaluateOnNewDocument", identifier: recorder["identifier"]) if recorder
  end
end
