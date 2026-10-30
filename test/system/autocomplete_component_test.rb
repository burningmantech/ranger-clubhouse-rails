# frozen_string_literal: true

require "application_system_test_case"

class AutocompleteComponentTest < ApplicationSystemTestCase
  include TimesheetAdminTestHelper

  setup do
    @person = person(:active_ranger)
    ensure_role(Role::EVENT_MANAGEMENT, "Event Management")
    grant_role(@person, Role::EVENT_MANAGEMENT)
    sign_in(@person)
  end

  test "typing query opens results dropdown" do
    visit test_harness_autocomplete_path

    input = find("#test-autocomplete-input")
    input.fill_in with: "Test"

    # Wait for results to appear
    assert_selector "[data-autocomplete-target='results']:not([hidden])", wait: 5
    assert_selector "[role='option']", minimum: 1
  end

  test "ArrowDown selects next option" do
    visit test_harness_autocomplete_path

    input = find("#test-autocomplete-input")
    input.fill_in with: "Test"

    assert_selector "[role='option']", minimum: 1, wait: 5

    input.send_keys(:arrow_down)
    assert_selector "[role='option'][aria-selected='true']", count: 1
  end

  test "ArrowUp selects previous option and wraps to last" do
    visit test_harness_autocomplete_path

    input = find("#test-autocomplete-input")
    input.fill_in with: "Test"

    assert_selector "[role='option']", minimum: 1, wait: 5

    # ArrowUp from no selection wraps to last option
    input.send_keys(:arrow_up)
    assert_selector "[role='option'][aria-selected='true']", count: 1
  end

  test "Enter commits selected option" do
    visit test_harness_autocomplete_path

    input = find("#test-autocomplete-input")
    input.fill_in with: "Test"

    assert_selector "[role='option']", minimum: 1, wait: 5

    input.send_keys(:arrow_down)
    input.send_keys(:enter)

    # Results should close after selection
    assert_no_selector "[data-autocomplete-target='results']:not([hidden])", wait: 2

    # Hidden field should be populated
    hidden = find("#selected-person-id", visible: false)
    assert hidden.value.present?, "Hidden field should have a value after selection"
  end

  test "Tab takes the highlighted option in a form field" do
    visit test_harness_autocomplete_path

    input = find("#test-autocomplete-input")
    input.fill_in with: "Test"

    assert_selector "#test-autocomplete-results [role='option']", minimum: 2, wait: 5

    input.send_keys(:arrow_down, :tab)

    # The row has no page to open here: it fills the field on the way out.
    hidden = find("#selected-person-id", visible: false)
    assert hidden.value.present?, "Tab should take the highlighted option"
  end

  test "Tab pressed while a new search is in flight takes nothing" do
    visit test_harness_autocomplete_path

    input = find("#test-autocomplete-input")
    input.fill_in with: "CustomGender"
    assert_selector "#test-autocomplete-results [role='option'][aria-selected='true']", count: 1, wait: 5

    # The text is replaced and Tab pressed in one breath. The row on screen,
    # highlight and all, is still CustomGender's, and is not what was typed.
    input.send_keys(*([:backspace] * "CustomGender".length), "Test", :tab)

    assert_equal "Test", input.value, "The previous search's person was written over the text"
    assert find("#selected-person-id", visible: false).value.blank?,
           "Tab took a row left over from the previous search"
  end

  test "Escape closes results dropdown" do
    visit test_harness_autocomplete_path

    input = find("#test-autocomplete-input")
    input.fill_in with: "Test"

    assert_selector "[data-autocomplete-target='results']:not([hidden])", wait: 5

    input.send_keys(:escape)

    assert_no_selector "[data-autocomplete-target='results']:not([hidden])", wait: 2
  end

  test "results are accessible with role=option elements" do
    visit test_harness_autocomplete_path

    input = find("#test-autocomplete-input")
    input.fill_in with: "Test"

    assert_selector "[role='option']", minimum: 1, wait: 5

    # All options should have data-autocomplete-value
    all("[role='option']").each do |option|
      assert option["data-autocomplete-value"].present?,
             "Each option should have a data-autocomplete-value"
    end
  end

  test "short query shows minimum length message" do
    visit test_harness_autocomplete_path

    input = find("#test-autocomplete-input")
    input.fill_in with: "T"

    # Should not show results for single character
    assert_no_selector "[role='option']", wait: 1
  end

  test "recents render on empty query when input is focused" do
    visit test_harness_autocomplete_path

    # Seed localStorage with recent entries for the recents variant
    page.execute_script(<<~JS)
      localStorage.setItem("ac-recents-test_recents", JSON.stringify([
        { value: "Hubcap", label: "Hubcap" },
        { value: "Danger Ranger", label: "Danger Ranger" }
      ]))
    JS

    # Focus the recents-enabled input (empty value)
    input = find("#test-recents-autocomplete-input")
    input.click

    # Recent entries should appear
    assert_selector "[role='option']", minimum: 2, wait: 3

    # Verify the "Recent" header is shown (CSS uppercase transforms to "RECENT")
    assert_selector ".ac-group-header", text: "RECENT"

    # Select a recent entry with keyboard
    input.send_keys(:arrow_down)
    input.send_keys(:enter)

    # Hidden field should be populated from recents selection
    hidden = find("#selected-person-id-recents", visible: false)
    assert hidden.value.present?, "Hidden field should have a value after selecting a recent"
  end

  test "recents come back, and can be picked, once the text is cleared" do
    visit test_harness_autocomplete_path

    page.execute_script(<<~JS)
      localStorage.setItem("ac-recents-test_recents", JSON.stringify([
        { value: "Hubcap", label: "Hubcap" }
      ]))
    JS

    # A search first: its results carry the filter bar, which recents never do.
    input = find("#test-recents-autocomplete-input")
    input.fill_in with: "Test"
    assert_selector "#recents-fixture .ac-filter-bar", wait: 5

    # Clearing the text key by key swaps the results for the recents...
    input.send_keys(*([:backspace] * 4))
    assert_selector "#recents-fixture .ac-group-header", text: "RECENT", wait: 5
    assert_no_selector "#recents-fixture .ac-filter-bar"

    # ...and the list is settled again, so Enter picks one rather than waiting
    # for a search that is not coming.
    input.send_keys(:arrow_down, :enter)

    hidden = find("#selected-person-id-recents", visible: false)
    assert_equal "Hubcap", hidden.value
  end

  test "Enter pressed while fetch is in flight auto-selects the sole result when it lands" do
    visit test_harness_autocomplete_path

    # Slow the autocomplete fetch so we can press Enter before it resolves.
    page.execute_script(<<~JS)
      const realFetch = window.fetch
      window.fetch = (...args) =>
        new Promise(resolve => setTimeout(() => resolve(realFetch(...args)), 800))
    JS

    input = find("#test-autocomplete-input")

    # "ProspectiveNewbie" is a unique callsign -> exactly one result.
    input.fill_in with: "ProspectiveNewbie"

    # Press Enter immediately, while the (delayed) fetch is still in flight and
    # no results have rendered yet.
    input.send_keys(:enter)

    # The queued Enter must auto-select the sole result once it lands: the hidden
    # field becomes populated even though Enter preceded the response. Poll the
    # JS-set value (Capybara value matchers don't auto-wait on script-set values).
    assert_eventually("Sole result should commit when Enter preceded the response") do
      page.evaluate_script("document.getElementById('selected-person-id').value") != ""
    end

    # Results are closed after the auto-commit.
    assert_no_selector "[data-autocomplete-target='results']:not([hidden])"
  end

  test "typing over a chosen person clears the id with the keystroke" do
    visit test_harness_autocomplete_path

    # A person already chosen, as an edit form renders one, and a note of what a
    # form submitted on the next keystroke would send. The listener is on the
    # document, so it runs after the controller's own.
    page.execute_script(<<~JS)
      const hidden = document.getElementById("selected-person-id")
      hidden.value = "42"
      document.addEventListener("input", () => { window.idAtKeystroke = hidden.value }, {once: true})
    JS
    find("#test-autocomplete-input").send_keys("x")

    assert_equal "", page.evaluate_script("window.idAtKeystroke"),
                 "The id of the person typed over was still there to submit"
  end

  test "a row clicked just after a keystroke keeps its person, and no search follows" do
    visit test_harness_autocomplete_path

    input = find("#test-autocomplete-input")
    input.fill_in with: "Test"
    option = "#test-autocomplete-results [role='option']"
    assert_selector option, minimum: 2, wait: 5
    row = first(option)
    id = row["data-autocomplete-value"]
    count_searches

    # One more letter, and a click on a row of the list still up, inside the
    # debounce the letter started.
    type_then_click("R", row)
    wait_out_debounce

    # The click was the choice, and the search for the letter is called off. It
    # used to run: it wiped the id just chosen and put a list back up.
    assert_equal id, find("#selected-person-id", visible: false).value
    assert_equal 0, searches, "A search ran after the row was chosen"
  end

  test "Escape before the first results calls off the search and the Enter waiting for it" do
    visit test_harness_autocomplete_path
    count_searches
    input = find("#test-autocomplete-input")

    # One person's callsign, Enter and Escape in one breath. No list is up, and
    # the Enter is waiting for a search that has not started.
    input.send_keys("ProspectiveNewbie", :enter, :escape)
    wait_out_debounce
    assert_equal 0, searches, "Escape did not call off the search"

    # The Enter went with the search. Typed on, the callsign finds its one
    # person, who is highlighted and not chosen.
    input.send_keys("e")
    assert_selector "#test-autocomplete-results [role='option'][aria-selected='true']", count: 1, wait: 5
    assert find("#selected-person-id", visible: false).value.blank?, "The Enter outlived the Escape"
  end

  test "moving the component does not lengthen the wait before a search" do
    visit test_harness_autocomplete_path
    count_searches

    # Stimulus disconnects and reconnects the same controller when its element
    # is moved, and each connect used to put another 300ms on the debounce. The
    # count is read 450ms after the last keystroke: past one delay, short of two.
    page.execute_script(<<~JS)
      const element = document.getElementById("test-autocomplete")
      element.parentNode.append(element)

      let timer
      document.addEventListener("input", () => {
        clearTimeout(timer)
        timer = setTimeout(() => {
          document.documentElement.dataset.searchesInTime = window.searchesStarted
        }, 450)
      })
    JS

    find("#test-autocomplete-input").send_keys("Test")

    assert_selector "html[data-searches-in-time='1']", visible: :all, wait: 5
  end

  test "the Enter that confirms an input method's composition is not taken for the list" do
    visit test_harness_autocomplete_path

    # One person, highlighted as the result lands, so any Enter taken chooses.
    find("#test-autocomplete-input").fill_in with: "ProspectiveNewbie"
    sole = "#test-autocomplete-results [role='option'][aria-selected='true']"
    assert_selector sole, count: 1, wait: 5
    hidden = find("#selected-person-id", visible: false)

    # That Enter arrives with keyCode 229: in Chrome while the text is still
    # composing, in Safari just after. Neither is the user choosing the person.
    press_enter(key_code: 229, composing: true)
    press_enter(key_code: 229, composing: false)
    assert_selector sole, count: 1
    assert hidden.value.blank?, "An input method's Enter chose the person"

    # A phone keyboard composes the word being typed and sends its Enter as a
    # plain key. That one is the user's, composing or not.
    press_enter(key_code: 13, composing: true)
    assert hidden.value.present?, "A plain Enter pressed mid-composition was dropped"
  end

  test "a press on the list let go outside it does not stop a later blur from closing the list" do
    visit test_harness_autocomplete_path

    input = find("#test-autocomplete-input")
    input.fill_in with: "Test"
    results = "#test-autocomplete-results"
    assert_selector "#{results} [role='option']", minimum: 2, wait: 5

    # Pressed on a row, dragged off the list and let go on the page heading.
    heading = find("h1")
    first("#{results} [role='option']").drag_to(heading)

    # Back into the field, then out of it: the list closes as it always does.
    input.click
    heading.click
    assert_no_selector "#{results}:not([hidden])"
  end

  test "a search that fails after the text has changed shows no error" do
    visit test_harness_autocomplete_path

    # The search for "Test" never answers. It fails, as a dropped connection
    # fails it, right after the next keystroke.
    page.execute_script(<<~JS)
      const realFetch = window.fetch
      window.fetch = (...args) => {
        if (new URL(String(args[0]), location.href).searchParams.get("q") !== "Test") return realFetch(...args)
        document.documentElement.dataset.searchOut = "true"
        return new Promise((_resolve, reject) => {
          document.addEventListener("input", () => {
            setTimeout(() => reject(new TypeError("Failed to fetch")), 0)
          }, {once: true})
        })
      }
      new MutationObserver(() => {
        if (document.querySelector(".ac-error")) document.documentElement.dataset.errorShown = "true"
      }).observe(document.body, {childList: true, subtree: true})
    JS

    input = find("#test-autocomplete-input")
    input.send_keys("Test")
    assert_selector "html[data-search-out='true']", visible: :all, wait: 5

    input.send_keys("R")

    # "TestR" is one person. The search before it failed with nobody waiting on
    # it, and said nothing.
    assert_selector "#test-autocomplete-results [role='option']", count: 1, wait: 5
    assert_no_selector "html[data-error-shown='true']", visible: :all
  end

  test "select-on-blur commits the sole result when focus leaves the input" do
    visit test_harness_autocomplete_path

    input = find("#test-blur-autocomplete-input")
    input.fill_in with: "CustomGender"

    # Sole result renders inline.
    assert_selector "#blur-fixture [role='option']", count: 1, wait: 5

    # Move focus away from the input (no keyboard highlight set).
    find("#blur-sink").click

    # The sole result commits on blur, populating the hidden field.
    hidden = find("#selected-person-id-blur", visible: false)
    assert hidden.value.present?,
           "Sole result should commit on blur via select-on-blur"
  end

  test "select-on-blur commits the highlighted result when focus leaves the input" do
    visit test_harness_autocomplete_path

    input = find("#test-blur-autocomplete-input")
    # "Test" matches multiple people, so a highlight (not sole) drives the commit.
    input.fill_in with: "Test"

    assert_selector "#blur-fixture [role='option']", minimum: 2, wait: 5

    # Highlight the first result via keyboard, then blur.
    input.send_keys(:arrow_down)
    assert_selector "#blur-fixture [role='option'][aria-selected='true']", count: 1

    find("#blur-sink").click

    hidden = find("#selected-person-id-blur", visible: false)
    assert hidden.value.present?,
           "Highlighted result should commit on blur via select-on-blur"
  end

  test "select-on-blur commits nothing when several results are shown and none is highlighted" do
    visit test_harness_autocomplete_path

    input = find("#test-blur-autocomplete-input")
    # "Test" matches multiple people and nothing is highlighted: no choice was made.
    input.fill_in with: "Test"

    assert_selector "#blur-fixture [role='option']", minimum: 2, wait: 5

    find("#blur-sink").click

    # The list closes and the first match is not picked for the user.
    assert_no_selector "#test-blur-autocomplete-results:not([hidden])"
    hidden = find("#selected-person-id-blur", visible: false)
    assert hidden.value.blank?,
           "Blur with several results and no highlight should commit nothing"
  end

  test "select-on-blur commits nothing while the list is still the previous search's" do
    visit test_harness_autocomplete_path

    input = find("#test-blur-autocomplete-input")
    input.fill_in with: "CustomGender"
    assert_selector "#blur-fixture [role='option'][aria-selected='true']", count: 1, wait: 5

    # The text is replaced and the field left in one breath. The row on screen,
    # highlight and all, is still CustomGender's, and is not what was typed.
    type_then_click(*([:backspace] * "CustomGender".length), "Test", find("#blur-sink"))

    assert_equal "Test", input.value, "The previous search's person was written over the text"
    assert find("#selected-person-id-blur", visible: false).value.blank?,
           "Blur committed a row left over from the previous search"
  end

  test "picking a filter chip returns focus to the input" do
    visit test_harness_autocomplete_path

    input = find("#test-autocomplete-input")
    input.fill_in with: "Test"

    results = "#test-autocomplete-results"
    assert_selector "#{results} .ac-filter-chip", minimum: 2, wait: 5

    find("#{results} .ac-filter-chip[data-autocomplete-filter-value='auditor']").click

    # The chip is applied and typing can carry on: the click did not strand
    # focus on a chip the re-render throws away.
    assert_selector "#{results} .ac-filter-chip-active[data-autocomplete-filter-value='auditor']", wait: 5
    assert_selector "#test-autocomplete-input:focus"
  end

  test "embedded results render inline without floating dropdown positioning" do
    visit test_harness_autocomplete_path

    input = find("#test-blur-autocomplete-input")
    input.fill_in with: "Test"

    assert_selector "#blur-fixture [role='option']", minimum: 1, wait: 5

    results = find("#test-blur-autocomplete-results")
    assert results[:class].include?("ac-results-inline"),
           "Embedded results should carry the ac-results-inline class"

    # Inline results sit in normal flow (static), not absolutely positioned, and
    # the above/below flip is bypassed.
    position = page.evaluate_script(
      "getComputedStyle(document.getElementById('test-blur-autocomplete-results')).position"
    )
    assert_equal "static", position,
                 "Inline results should use static positioning, not the floating dropdown"
    refute results[:class].include?("ac-results-above"),
           "Inline results should not receive the above-placement flip class"
  end

  test "ArrowUp keeps the selected option clear of the sticky filter bar" do
    # The fixture asks for five matches per field, so five people matched by
    # callsign and five by name make ten rows: more than the list shows at once.
    5.times { |i| create_person("Scroller#{i}", first_name: "Callsign") }
    5.times { |i| create_person("Byname#{i}", first_name: "Scroller") }

    visit test_harness_autocomplete_path

    input = find("#test-blur-autocomplete-input")
    input.fill_in with: "Scroller"

    assert_selector "#blur-fixture .ac-filter-bar .ac-filter-chip", wait: 5
    assert_selector "#blur-fixture [role='option']", count: 10

    # ArrowUp with nothing selected wraps to the last row; nine more walk back to
    # the first. The rows that scroll in from above are the ones the filter bar
    # used to cover.
    10.times do |press|
      input.send_keys(:arrow_up)

      assert_eventually("Selected option should be fully visible after ArrowUp #{press + 1}") do
        selected_option_fully_visible?("test-blur-autocomplete-results")
      end
    end
  end

  test "results container gets ac-results-above class when near bottom of viewport" do
    visit test_harness_autocomplete_path

    # Scroll to the placement fixture at the bottom
    page.execute_script("document.getElementById('placement-fixture').scrollIntoView()")

    input = find("#test-placement-autocomplete-input")
    input.fill_in with: "Test"

    # Wait for results to appear
    assert_selector "[role='option']", minimum: 1, wait: 5

    # Results container should have the above-placement class
    results = find("#test-placement-autocomplete-results")
    assert results[:class].include?("ac-results-above"),
           "Results container should have ac-results-above class when positioned near viewport bottom"
  end

  private

  # Keys and then a click, sent as one command, so the click lands inside the
  # debounce the keys started. The pointer's move is given no time: by default it
  # takes 250ms of the 300.
  def type_then_click(*keys, element)
    page.driver.browser.action(duration: 0).send_keys(*keys).click(element.native).perform
  end

  # An Enter keydown built by hand: a real key press cannot carry the keyCode and
  # composing flag a browser gives a key pressed during an input method's
  # composition.
  def press_enter(key_code:, composing:)
    page.execute_script(<<~JS, key_code, composing)
      document.getElementById("test-autocomplete-input").dispatchEvent(new KeyboardEvent("keydown", {
        key: "Enter", keyCode: arguments[0], isComposing: arguments[1], bubbles: true, cancelable: true
      }))
    JS
  end

  # Count the searches started from here on.
  def count_searches
    page.execute_script(<<~JS)
      window.searchesStarted = 0
      document.addEventListener("autocomplete.loadstart", () => { window.searchesStarted++ })
    JS
  end

  def searches
    page.evaluate_script("window.searchesStarted")
  end

  # Whether the highlighted option sits wholly in the part of the list a user
  # can see: below the sticky filter bar and above the list's bottom edge.
  def selected_option_fully_visible?(list_id)
    page.evaluate_script(<<~JS)
      (() => {
        const list = document.getElementById("#{list_id}")
        const option = list.querySelector("[role='option'][aria-selected='true']").getBoundingClientRect()
        const bar = list.querySelector(".ac-filter-bar").getBoundingClientRect()
        return Math.round(option.top - bar.bottom) >= 0 &&
          Math.round(list.getBoundingClientRect().bottom - option.bottom) >= 0
      })()
    JS
  end
end
