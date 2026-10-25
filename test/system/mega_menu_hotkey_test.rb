# frozen_string_literal: true

require "application_system_test_case"

class MegaMenuHotkeyTest < ApplicationSystemTestCase
  include TimesheetAdminTestHelper
  include MegaMenuTestHelper

  MEGA = "#mega-menu-dialog[open]"
  SEARCH = "[data-search-bar-target='dialog'][open]"

  setup do
    @person = person(:active_ranger)
    offer_mega_menu_to(@person)
    sign_in(@person)
  end

  test "Ctrl+Shift+K opens the mega menu and Cmd+Shift+K toggles it closed" do
    visit me_root_path
    assert_no_selector MEGA

    dispatch_hotkey(ctrl: true)
    assert_selector MEGA, wait: 2

    dispatch_hotkey(meta: true)
    assert_no_selector MEGA, wait: 2
  end

  test "the shifted chord opens the menu and the unshifted one opens the search bar" do
    visit me_root_path

    dispatch_hotkey(ctrl: true)
    assert_selector MEGA, wait: 2
    assert page.has_no_selector?(SEARCH),
           "Ctrl+Shift+K must not reach the search bar"
  end

  test "opening one dialog closes the other rather than stacking two modals" do
    # The search bar is role-gated; without it there is no second modal to stack.
    ensure_role(Role::EVENT_MANAGEMENT, "Event Management")
    grant_role(@person, Role::EVENT_MANAGEMENT)
    sign_in(@person)
    visit me_root_path

    # Search bar first, then the menu on top of it.
    page.execute_script(<<~JS)
      document.dispatchEvent(new KeyboardEvent("keydown",
        { key: "k", ctrlKey: true, bubbles: true, cancelable: true }))
    JS
    assert_selector SEARCH, wait: 2

    dispatch_hotkey(ctrl: true)
    assert_selector MEGA, wait: 2
    assert page.has_no_selector?(SEARCH),
           "the search dialog must not stay open beneath the menu"
  end

  test "hotkey does not open the menu when focus is in a rich text editor" do
    visit me_root_path

    page.execute_script(<<~JS)
      const editor = document.createElement("div")
      editor.id = "test-editor"
      editor.contentEditable = "true"
      document.body.appendChild(editor)
      editor.focus()
    JS

    dispatch_hotkey(ctrl: true)
    assert_no_selector MEGA
  end

  test "closing the menu clears the filter box" do
    visit me_root_path

    dispatch_hotkey(ctrl: true)
    assert_selector MEGA, wait: 2

    field = find("#mega-menu-search", wait: 5)
    field.fill_in with: "timesheet"
    assert_equal "timesheet", find("#mega-menu-search").value

    dispatch_hotkey(ctrl: true)
    assert_no_selector MEGA, wait: 2

    dispatch_hotkey(ctrl: true)
    assert_selector MEGA, wait: 2
    assert_equal "", find("#mega-menu-search").value,
                 "reopening must not resume the previous search"
  end

  private

    # A real press of the chord reports an uppercase "K"; Stimulus lowercases
    # both sides, and dispatching the lowercase form would pass while hiding
    # that.
    def dispatch_hotkey(ctrl: false, meta: false)
      page.execute_script(<<~JS, ctrl, meta)
        document.dispatchEvent(new KeyboardEvent("keydown", {
          key: "K",
          ctrlKey: arguments[0],
          metaKey: arguments[1],
          shiftKey: true,
          bubbles: true,
          cancelable: true
        }))
      JS
    end
end
