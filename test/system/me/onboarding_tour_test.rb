# frozen_string_literal: true

require "application_system_test_case"

# The first-sign-in tour on /me: driver.js driven by the onboarding controller
# from the step templates in me/dashboard/_onboarding.
class Me::OnboardingTourTest < ApplicationSystemTestCase
  include MegaMenuTestHelper

  setup do
    @person = person(:active_ranger)
    offer_mega_menu_to(@person)
    Document.create!(tag: Document::DASHBOARD_LINKS_RANGER_TAG, description: "Dashboard links",
                     body: %(<p><a href="https://example.com/manual">Ranger Manual</a></p>),
                     person_create_id: @person.id, person_update_id: @person.id)
    sign_in(@person) # marks the person toured (SystemTestHelpers)
    @person.update_column(:on_boarded_at, nil)
  end

  test "a ranger is walked through the dashboard once, and the walk is recorded" do
    # Short enough that the dashboard scrolls, so Done has somewhere to come back from.
    page.driver.browser.manage.window.resize_to(1400, 600)
    visit me_root_path

    assert_selector ".driver-popover-title", text: "Welcome, Ranger #{@person.callsign}"
    click_on "Next"
    assert_selector ".driver-popover-title", text: "Links Look Like This"
    click_on "Next"
    # Above lg the open sidebar is the step; the hamburger is display:none and dropped.
    assert_selector "#sidebar-drawer-content.driver-active-element"
    assert_selector ".driver-popover-title", text: "Your Sidebar"
    click_on "Next"
    assert_selector ".driver-popover-title", text: "The Menu Button"
    # The page's shortcuts stay out of the tour: the menu would be unclickable
    # under the overlay, and closing it with Escape would end the tour.
    page.driver.browser.action.key_down(:control).key_down(:shift).send_keys("k").key_up(:shift).key_up(:control).perform
    assert_no_selector "dialog[open]"
    click_on "Next"
    assert_selector ".account-menu.driver-active-element"
    assert_selector ".driver-popover-title", text: "Account Menu"
    click_on "Next"
    assert_selector "#bug-report.driver-active-element"
    assert_selector ".driver-popover-title", text: "File A Bug Report"
    # A double-click on Next moves one step: the second click lands while the
    # scroll to Links & Things is pending and is ignored.
    find(".driver-popover-next-btn").double_click
    assert_selector "#links-and-things > [role=heading].driver-active-element"
    assert_selector ".driver-popover-title", text: "Links & Things"
    assert_eventually("driver should have scrolled down to Links & Things") { scroll_top.positive? }
    assert_no_selector "#toast-container [role=status]"
    click_on "Done"

    assert_no_selector ".driver-popover"
    assert_no_selector "[data-controller=onboarding]"
    assert_selector "#toast-container [role=status]", text: "Tour complete. Replay it any time from the Account menu."
    assert_toured
    assert_eventually("Done did not scroll the page back to the top") { scroll_top.zero? }
  ensure
    page.driver.browser.manage.window.resize_to(1400, 1400)
  end

  test "on a phone the sidebar step points at the hamburger" do
    on_a_phone do
      visit me_root_path

      assert_selector ".driver-popover-title", text: "Welcome, Ranger"
      click_on "Next"
      click_on "Next"
      assert_selector "#sidebar-toggle.driver-active-element"
      assert_selector ".driver-popover-title", text: "Your Sidebar"
      # The hidden drawer's step was dropped, so the Menu button comes next.
      click_on "Next"
      assert_selector "#menu-open-phone.driver-active-element"
      assert_selector ".driver-popover-title", text: "The Menu Button"
    end
  end

  test "skipping the tour counts as taking it, and a replay records nothing" do
    visit me_root_path
    assert_selector ".driver-popover-title", text: "Welcome, Ranger"

    find(".driver-popover-close-btn").click

    assert_no_selector ".driver-popover"
    assert_no_selector "#toast-container [role=status]"
    assert_toured
    taken = @person.on_boarded_at

    visit me_root_path(tour: 1)
    assert_selector ".driver-popover-title", text: "Welcome, Ranger"
    find(".driver-popover-close-btn").click
    assert_no_selector ".driver-popover"
    assert_no_selector "[data-controller=onboarding]"
    # A page load after the close: any write a replay sent would have landed
    # by the time the next request is served.
    visit me_root_path
    assert_no_selector ".driver-popover"
    assert_equal taken, @person.reload.on_boarded_at
  end

  # A Ranger with no roles has no Menu button, and the tour has no step for
  # it: the sidebar step goes straight on to the Account Menu.
  test "a person the menu is not offered to gets no Menu step" do
    ranger = person(:ranger_with_custom_gender)
    sign_in(ranger)
    ranger.update_column(:on_boarded_at, nil)
    visit me_root_path

    assert_selector ".driver-popover-title", text: "Welcome, Ranger"
    click_on "Next"
    click_on "Next"
    assert_selector ".driver-popover-title", text: "Your Sidebar"
    click_on "Next"
    assert_selector ".driver-popover-title", text: "Account Menu"
    assert_selector ".driver-popover-progress-text", text: "4 of 6"
  end

  # driver writes the popover title as HTML; a callsign is text to it.
  test "a callsign with markup is shown as text in the welcome title" do
    @person.update_columns(callsign: "Test <b>Ranger</b>", callsign_normalized: "test<b>ranger</b>")
    visit me_root_path

    assert_selector ".driver-popover-title", text: "Welcome, Ranger Test <b>Ranger</b>"
    assert_no_selector ".driver-popover-title b"
  end

  private

  # The write is a fetch the controller sends as the tour closes, after the DOM
  # has nothing left to wait on.
  def assert_toured
    assert_eventually("on_boarded_at was not recorded") { @person.reload.on_boarded_at }
  end

  # /me scrolls inside the drawer's content pane, not the window.
  def scroll_top
    page.evaluate_script("document.querySelector('.drawer-content').scrollTop")
  end
end
