# frozen_string_literal: true

require "application_system_test_case"

# A copy is answered on the control that was pressed -- a tip over it, and a
# line in the layout's live region for a screen reader -- not by a toast across
# the page.
class CopyToClipboardTest < ApplicationSystemTestCase
  include TimesheetAdminTestHelper # ensure_role / grant_role

  CONTROL = "[data-controller='copy-to-clipboard']"

  setup do
    tech_ninja = person(:echelon_ranger)
    ensure_role(Role::TECH_NINJA, "Tech Ninja")
    grant_role(tech_ninja, Role::TECH_NINJA)
    sign_in(tech_ninja)

    visit admin_oauth_clients_path
    # The real clipboard wants a focused window and a permission. What was
    # handed to it is all these need.
    execute_script(<<~JS)
      Object.defineProperty(navigator, "clipboard",
        { value: { writeText: async (text) => { window.copied = text } } })
    JS
  end

  test "a copy is answered by a tip over the control" do
    control = first(CONTROL)
    control.click

    assert_selector "#{CONTROL} > .copy-tip", text: "Copied", count: 1
    assert_equal control["data-copy-to-clipboard-content-value"], evaluate_script("window.copied")
    assert_selector "#live-region", text: "Copied", visible: :all
    assert_no_selector ".toast-base"

    # Over the control it belongs to: centred on it, just clear of its top edge.
    tip, button = evaluate_script(<<~JS)
      [".copy-tip", "#{CONTROL}"].map((selector) => document.querySelector(selector).getBoundingClientRect().toJSON())
    JS
    assert_in_delta button["x"] + button["width"] / 2, tip["x"] + tip["width"] / 2, 1
    assert_operator tip["bottom"], :<=, button["top"]
    assert_operator button["top"] - tip["bottom"], :<, 16
  end

  # Both presses are waiting on the clipboard before either is answered. The
  # second answer used to forget the first one's tip, which then never left.
  # This is also the one place that waits the tip out: the wait is real time,
  # and one case that pays for it is enough.
  test "two presses at once leave one tip, and then nothing" do
    execute_script("const control = document.querySelector(arguments[0]); control.click(); control.click()", CONTROL)

    assert_selector ".copy-tip", count: 1
    assert_no_selector ".copy-tip", wait: 5
    assert_no_selector "#live-region *", visible: :all
  end
end
