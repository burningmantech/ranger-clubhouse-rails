# frozen_string_literal: true

require "application_system_test_case"

# The live region's lines (controllers/live_region.js): heard where they land,
# and gone from the copy of the page Turbo keeps for Back.
class LiveRegionTest < ApplicationSystemTestCase
  include TimesheetAdminTestHelper

  setup do
    @person = person(:active_ranger)
    sign_in(@person)
  end

  # Turbo copies the page before the old body leaves, so a line a controller
  # takes down on disconnect would still be in the copy, stale and nobody's.
  test "a line is not kept in the page Back restores" do
    visit me_root_path
    execute_script(<<~JS)
      document.getElementById("live-region").append(Object.assign(document.createElement("div"), { textContent: "Sorted by Name, ascending." }))
    JS
    assert_selector "#live-region", text: "Sorted by Name", visible: :all

    execute_script("Turbo.visit('/me/schedule')")
    assert_current_path me_schedule_path
    page.go_back
    assert_current_path me_root_path
    assert_no_selector "#live-region *", visible: :all
  end

  # Everything outside a modal dialog is inert, the page's region included, so
  # the search bar's count goes to the region inside its dialog.
  test "a search's result count is announced inside the search dialog" do
    ensure_role(Role::EVENT_MANAGEMENT, "Event Management")
    grant_role(@person, Role::EVENT_MANAGEMENT)
    visit test_harness_search_bar_path

    # Controllers load lazily: a click before the search bar's connects opens nothing.
    wait_for_controller("search-bar", "[data-controller~='search-bar']")
    execute_script("document.querySelector(\"[data-action='search-bar#open']\").click()")
    assert_selector "[data-search-bar-target='dialog'][open]", wait: 2
    find("[data-search-bar-target='input']").fill_in with: "Test"

    assert_selector "dialog[open] [data-live-region]", text: /\d+ results? available/, visible: :all, wait: 5
  end
end
