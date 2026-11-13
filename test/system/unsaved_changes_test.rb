# frozen_string_literal: true

require "application_system_test_case"

# unsaved_changes_controller.js: leaving a page with an edited form asks in the
# app's own dialog, which application.js fills from #confirm-dialog-template.
class UnsavedChangesTest < ApplicationSystemTestCase
  setup do
    @person = person(:active_ranger)
    sign_in(@person)
    visit me_root_path
    assert_selector "h1", text: "Welcome Ranger #{@person.callsign}"

    page.execute_script(<<~JS)
      document.querySelector("main").insertAdjacentHTML("beforeend",
        '<form id="draft-form" data-controller="unsaved-changes"><input id="draft" name="draft"></form>')
    JS
    wait_for_controller "unsaved-changes", "#draft-form"
    fill_in "draft", with: "Half a message"
  end

  test "a link away asks first: staying keeps the page and its edits, leaving follows the link" do
    find("a[href='#{me_schedule_path}']", match: :first).click

    within "#turbo-confirm-modal dialog[open]" do
      assert_selector "h3", text: "Unsaved Changes"
      assert_text "Leave this page? Your changes have not been saved and will be lost."
      assert_selector "button.btn-error", text: "Leave Page"
      click_button "Stay on Page"
    end

    assert_no_selector "#turbo-confirm-modal dialog[open]"
    assert_current_path me_root_path
    assert_field "draft", with: "Half a message"

    find("a[href='#{me_schedule_path}']", match: :first).click
    within("#turbo-confirm-modal dialog[open]") { click_button "Leave Page" }

    assert_current_path me_schedule_path
  end

  # A dialog a render took away answered nothing: the next link asks again
  # instead of every visit being refused.
  test "a question that vanished unanswered does not lock the page" do
    find("a[href='#{me_schedule_path}']", match: :first).click
    assert_selector "#turbo-confirm-modal dialog[open]"
    page.execute_script("document.querySelector('#turbo-confirm-modal dialog').remove()")

    find("a[href='#{me_schedule_path}']", match: :first).click
    within("#turbo-confirm-modal dialog[open]") { click_button "Leave Page" }

    assert_current_path me_schedule_path
  end
end
