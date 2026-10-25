# frozen_string_literal: true

require "application_system_test_case"

# Starring a link re-renders the whole menu from the server. The search filter
# is client state the server never sees, so the panel it picks for "search" is
# always wrong -- the controller has to put the filter back.
class MegaMenuFavoriteTest < ApplicationSystemTestCase
  include MegaMenuTestHelper

  MEGA = "#mega-menu-dialog[open]"
  # "Service Recognition" (/me/awards) is the only link matching "recognition".
  STAR = "#mega-star-search-me-awards"
  CATEGORY_STAR = "#mega-star-account-category-account"

  setup do
    @person = person(:active_ranger)
    offer_mega_menu_to(@person)
    sign_in(@person)
    visit me_root_path
    open_mega_menu
    find("#mega-menu-search", wait: 5).fill_in with: "recognition"
    assert_selector ".mega-menu-item", text: "Service Recognition", count: 1
  end

  test "starring a search result leaves the query, the filter, and the panel alone" do
    find(STAR).click

    assert_selector "#{STAR}.mega-menu-star-on", wait: 5
    assert PersonFavorite.exists?(person_id: @person.id, path: me_awards_path)

    assert_equal "recognition", find("#mega-menu-search").value,
                 "the re-render must not blank the search box"
    assert_selector ".mega-menu-panel[data-panel='search']"
    assert page.has_no_selector?(".mega-menu-panel[data-panel='favorites']"),
           "the menu must not fall back to the Favorites panel"
    assert_selector ".mega-menu-item", text: "Service Recognition", count: 1
  end

  test "starring a search result keeps focus on the star" do
    find(STAR).click

    assert_selector "#{STAR}.mega-menu-star-on:focus", wait: 5
  end

  # A link ignores Space; only a real button toggles from the keyboard this way.
  test "Space on a star toggles it" do
    find(STAR).send_keys(:space)

    assert_selector "#{STAR}[aria-pressed='true']", wait: 5
    assert PersonFavorite.exists?(person_id: @person.id, path: me_awards_path)
  end

  # Picking a panel ends the search; otherwise the star's re-render would
  # re-apply the stale filter and snap back to the results.
  test "starring a category heading after picking it from the side column stays on that panel" do
    find(".mega-menu-side button[data-panel='account']").click
    assert_equal "", find("#mega-menu-search").value

    find(CATEGORY_STAR).click

    assert_selector "#{CATEGORY_STAR}.mega-menu-star-on:focus", wait: 5
    assert_selector ".mega-menu-panel[data-panel='account']"
    assert page.has_no_selector?(".mega-menu-panel[data-panel='search']")
    assert PersonFavorite.exists?(person_id: @person.id, path: "category:account")
  end

  # The shortcut hides the panel it sits in, so focus would land on nothing
  test "opening a starred category from Favorites moves focus into its panel" do
    PersonFavorite.create!(person_id: @person.id, path: "category:account")
    visit me_root_path
    open_mega_menu

    find(".mega-menu-panel[data-panel='favorites'] .mega-menu-cat-btn[data-mega-menu-panel-param='account']",
         wait: 5).click

    assert_selector "#{CATEGORY_STAR}:focus", wait: 2
  end

  private

    def open_mega_menu
      page.execute_script(<<~JS)
        document.dispatchEvent(new KeyboardEvent("keydown",
          { key: "K", ctrlKey: true, shiftKey: true, bubbles: true, cancelable: true }))
      JS
      assert_selector MEGA, wait: 2
    end
end
