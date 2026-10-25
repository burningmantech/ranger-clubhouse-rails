# frozen_string_literal: true

require "application_system_test_case"

# The menu loads in a lazy frame and stars post through a form, and either can
# fail: no connection, or a sign-in that has expired. The menu says which,
# inside the dialog, without leaving the page. Chrome's own offline switch
# (DevTools Protocol) stands in for a lost connection.
class MegaMenuFailureTest < ApplicationSystemTestCase
  include MegaMenuTestHelper

  MEGA = "#mega-menu-dialog[open]"
  OFFLINE = "#mega-menu-dialog [data-kind='offline']"
  FAILED = "#mega-menu-dialog [data-kind='failed']"
  EXPIRED = "#mega-menu-dialog [data-kind='expired']"
  SLOW = "#mega-menu-dialog [data-kind='slow']"
  CATEGORY_STAR = "#mega-star-account-category-account"

  setup do
    @person = person(:active_ranger)
    offer_mega_menu_to(@person)
    sign_in(@person)
    visit me_root_path
  end

  # One browser serves the whole run: leave it online, with events off
  teardown do
    offline(false)
    page.driver.browser.execute_cdp("Network.disable")
  end

  test "a menu that cannot load says so, and Try Again loads it" do
    offline(true)
    open_mega_menu

    assert_selector OFFLINE, text: "Can't Reach the Clubhouse", wait: 5
    assert_selector "#{OFFLINE} button:focus", text: "Try Again"
    assert_selector "#mega-menu-dialog .mega-menu-frame", visible: :hidden

    # The hidden frame leaves bare dialog under the callout: a click there is
    # inside the box, not on the backdrop
    click_inside_dialog_below(OFFLINE)
    assert_selector MEGA

    offline(false)
    page.execute_script(<<~JS)
      window.frameVisits = 0
      document.querySelector("#mega-menu-dialog turbo-frame")
        .addEventListener("turbo:before-fetch-request", () => window.frameVisits++)
    JS
    click_on "Try Again"

    assert_selector "#mega-menu-search", wait: 5
    assert_selector OFFLINE, visible: :hidden
    assert_equal 1, page.evaluate_script("window.frameVisits"), "Try Again should start one visit"
  end

  test "a menu opened after the sign-in expired says so and stays on the page" do
    sign_out
    open_mega_menu

    assert_selector EXPIRED, text: "You've Been Signed Out", wait: 5
    assert_equal me_root_path, URI(current_url).path

    click_on "Sign In Again"

    assert_current_path root_path, wait: 5
  end

  test "a star that cannot reach the server says so above the menu and keeps focus" do
    open_account_panel
    offline(true)
    find(CATEGORY_STAR).click

    assert_selector OFFLINE, wait: 5
    assert_selector "#mega-menu-search"
    assert_selector "#{CATEGORY_STAR}:focus", wait: 2
    assert_not PersonFavorite.exists?(person_id: @person.id, path: "category:account")
  end

  test "a star pressed after the sign-in expired says so and stays on the page" do
    open_account_panel
    sign_out
    find(CATEGORY_STAR).click

    assert_selector EXPIRED, wait: 5
    assert_selector "#mega-menu-search"
    assert_equal me_root_path, URI(current_url).path
    assert_not PersonFavorite.exists?(person_id: @person.id, path: "category:account")
  end

  # Turbo's navigator paints the page a failed star answers with over the
  # whole page; the menu stops that and says so instead. (An empty 401 body
  # would leave the page alone anyway, so the test above can't show it.)
  test "a star answered with a server error page says so and stays on the page" do
    original = Me::FavoritesController.instance_method(:toggle)
    Me::FavoritesController.define_method(:toggle) do
      render html: "<h1 id='server-error-page'>We're sorry</h1>".html_safe,
             status: :internal_server_error, layout: false
    end
    open_account_panel
    find(CATEGORY_STAR).click

    assert_selector FAILED, text: "The Clubhouse Had a Problem", wait: 5
    assert_selector "#mega-menu-search"
    assert_no_selector "#server-error-page"
  ensure
    Me::FavoritesController.define_method(:toggle, original)
  end

  # Turbo keeps the page as it leaves it, attributes and all; a callout left
  # showing, and the hidden frame under it, must not come back with Back
  test "Back to a page whose menu failed brings back a menu that loads" do
    offline(true)
    open_mega_menu
    assert_selector OFFLINE, wait: 5
    click_on "Close Menu"
    offline(false)

    page.execute_script("document.body.dataset.cached = 'yes'")
    page.execute_script("Turbo.visit(#{me_awards_path.to_json})")
    assert_current_path me_awards_path, wait: 5
    page.go_back
    assert_current_path me_root_path, wait: 5
    assert_selector "body[data-cached='yes']", visible: :all

    open_mega_menu
    assert_selector "#mega-menu-search", wait: 5
    assert_selector OFFLINE, visible: :hidden
  end

  # Turbo reads a frame's body after its headers, and a body that never ends
  # sends no event: the slow warning has to outlast the headers
  test "a menu whose answer stalls after its headers says it is still loading" do
    page.execute_script(<<~JS)
      const realFetch = window.fetch
      window.fetch = (input, init) => String(input).includes(#{me_menu_path.to_json})
        ? Promise.resolve(new Response(new ReadableStream({ start() {} }),
                                       { status: 200, headers: { "Content-Type": "text/html" } }))
        : realFetch(input, init)
      const realSetTimeout = window.setTimeout
      window.setTimeout = (fn, ms, ...args) => realSetTimeout(fn, ms >= 10000 ? 100 : ms, ...args)
    JS
    open_mega_menu

    assert_selector SLOW, text: "Still Loading", wait: 5
  end

  private

    def open_mega_menu
      page.execute_script(<<~JS)
        document.dispatchEvent(new KeyboardEvent("keydown",
          { key: "K", ctrlKey: true, shiftKey: true, bubbles: true, cancelable: true }))
      JS
      assert_selector MEGA, wait: 2
    end

    def open_account_panel
      open_mega_menu
      find(".mega-menu-side button[data-panel='account']", wait: 5).click
      assert_selector CATEGORY_STAR
    end

    # A real pointer click 80px under the callout, inside the dialog's box
    def click_inside_dialog_below(callout)
      x, y = page.evaluate_script(<<~JS)
        (() => {
          const box = document.querySelector("#mega-menu-dialog").getBoundingClientRect()
          const shown = document.querySelector(#{callout.to_json}).getBoundingClientRect()
          return [Math.round(box.left + box.width / 2), Math.round(shown.bottom + 80)]
        })()
      JS
      page.driver.browser.action.move_to_location(x, y).click.perform
    end

    # Network.enable first: without it the emulation silently does nothing
    def offline(state)
      browser = page.driver.browser
      browser.execute_cdp("Network.enable")
      browser.execute_cdp("Network.emulateNetworkConditions",
                          offline: state, latency: 0, downloadThroughput: -1, uploadThroughput: -1)
    end
end
