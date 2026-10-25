# frozen_string_literal: true

require "application_system_test_case"

class SearchBarHotkeyTest < ApplicationSystemTestCase
  include TimesheetAdminTestHelper

  setup do
    @person = person(:active_ranger)
    ensure_role(Role::EVENT_MANAGEMENT, "Event Management")
    grant_role(@person, Role::EVENT_MANAGEMENT)
    sign_in(@person)
  end

  test "Ctrl+K opens search bar modal" do
    visit test_harness_search_bar_path

    # Modal should be hidden initially
    assert_no_selector "[data-search-bar-target='dialog'][open]"

    # Dispatch Ctrl+K via JS (Chrome headless intercepts native Ctrl+K)
    dispatch_hotkey("k", ctrl: true)

    # Modal should be visible
    assert_selector "[data-search-bar-target='dialog'][open]", wait: 2
  end

  test "Ctrl+K toggles search bar modal closed" do
    visit test_harness_search_bar_path

    # Open modal
    dispatch_hotkey("k", ctrl: true)
    assert_selector "[data-search-bar-target='dialog'][open]", wait: 2

    # Close with Ctrl+K
    dispatch_hotkey("k", ctrl: true)
    assert_no_selector "[data-search-bar-target='dialog'][open]", wait: 2
  end

  test "Escape closes search bar modal" do
    visit test_harness_search_bar_path

    # Open modal
    dispatch_hotkey("k", ctrl: true)
    assert_selector "[data-search-bar-target='dialog'][open]", wait: 2

    # Escape is the native dialog's own close: a real key press, since a
    # synthetic keydown has no default action.
    find("[data-search-bar-target='input']").send_keys(:escape)

    assert_no_selector "[data-search-bar-target='dialog'][open]", wait: 2
  end

  test "hotkey does not open when focus is in contenteditable" do
    visit test_harness_search_bar_path

    # Focus the contenteditable area
    find("#test-editor").click

    # Dispatch Ctrl+K while in editor
    dispatch_hotkey("k", ctrl: true)

    # Modal should remain hidden (editor intercept)
    assert_no_selector "[data-search-bar-target='dialog'][open]"
  end

  test "Cmd+K opens search bar modal" do
    visit test_harness_search_bar_path

    # Modal should be hidden initially
    assert_no_selector "[data-search-bar-target='dialog'][open]"

    # Dispatch Cmd+K via JS (macOS style)
    dispatch_hotkey("k", meta: true)

    # Modal should be visible
    assert_selector "[data-search-bar-target='dialog'][open]", wait: 2
  end

  test "search input receives focus when modal opens" do
    visit test_harness_search_bar_path

    dispatch_hotkey("k", ctrl: true)
    assert_selector "[data-search-bar-target='dialog'][open]", wait: 2

    # Assert focus via CSS :focus pseudo-class (matcher-driven wait)
    assert_selector "[data-search-bar-target='input']:focus", wait: 2
  end

  test "typing in the mounted modal renders grouped results inline" do
    visit test_harness_search_bar_path

    dispatch_hotkey("k", ctrl: true)
    assert_selector "[data-search-bar-target='dialog'][open]", wait: 2

    input = find("[data-search-bar-target='input']")
    input.fill_in with: "Test"

    # Results render inline inside the modal-box, grouped, with options.
    within "[data-search-bar-target='dialog']" do
      assert_selector "[data-autocomplete-target='results']:not([hidden])", wait: 5
      assert_selector ".ac-group-header", minimum: 1
      assert_selector "[role='option']", minimum: 1
    end

    # The results container uses the inline (non-floating) variant.
    results = find("[data-search-bar-target='dialog'] [data-autocomplete-target='results']")
    assert results[:class].include?("ac-results-inline"),
           "Modal results should use the inline variant"
  end

  test "Escape clears modal results before closing the modal" do
    visit test_harness_search_bar_path

    dispatch_hotkey("k", ctrl: true)
    assert_selector "[data-search-bar-target='dialog'][open]", wait: 2

    input = find("[data-search-bar-target='input']")
    input.fill_in with: "Test"
    assert_selector "[data-search-bar-target='dialog'] [data-autocomplete-target='results']:not([hidden])", wait: 5

    # First Escape (from the input) clears the results; the modal stays open.
    input.send_keys(:escape)
    assert_no_selector "[data-search-bar-target='dialog'] [data-autocomplete-target='results']:not([hidden])", wait: 2
    assert_selector "[data-search-bar-target='dialog'][open]"

    # Second Escape reaches the dialog itself and closes it.
    input.send_keys(:escape)
    assert_no_selector "[data-search-bar-target='dialog'][open]", wait: 2
  end

  # -------------------------------------------------------------------------
  # Focus leaving the search input (the dialog has no select-on-blur)
  # -------------------------------------------------------------------------

  test "losing focus never opens a result" do
    visit test_harness_search_bar_path
    count_visits

    dispatch_hotkey("k", ctrl: true)
    assert_selector "[data-search-bar-target='dialog'][open]", wait: 2

    option = "[data-search-bar-target='dialog'] [role='option']"
    input = find("[data-search-bar-target='input']")
    hint = find("[data-search-bar-target='modeHint']")

    # Several people, none highlighted: a click elsewhere in the dialog must not
    # pick the first of them. It empties the list, leaving no row behind, shown
    # or hidden, for a later key to open.
    input.fill_in with: "Test"
    assert_selector option, minimum: 2, wait: 5
    hint.click
    assert_no_selector option, visible: :all
    assert_equal 0, visits, "Blur with several results navigated"

    # One person, highlighted as it lands: still not opened by a blur.
    input.fill_in with: "ProspectiveNewbie"
    assert_selector "#{option}[aria-selected='true']", count: 1, wait: 5
    hint.click
    assert_no_selector option, visible: :all
    assert_equal 0, visits, "Blur with a sole result navigated"
  end

  test "Tab reaches the status chips and picking one returns focus to the input" do
    visit test_harness_search_bar_path

    dispatch_hotkey("k", ctrl: true)
    assert_selector "[data-search-bar-target='dialog'][open]", wait: 2

    modal = "[data-search-bar-target='dialog']"
    input = find("[data-search-bar-target='input']")
    input.fill_in with: "Test"
    assert_selector "#{modal} .ac-filter-chip", minimum: 2, wait: 5

    # Tab leaves the input for the first chip; the results stay where they are.
    input.send_keys(:tab)
    assert_selector "#{modal} .ac-filter-chip[data-autocomplete-filter-value='active_current']:focus"
    assert_selector "#{modal} [data-autocomplete-target='results']:not([hidden])"

    # On to the next chip, picked with the keyboard.
    page.send_keys(:tab)
    page.send_keys(:enter)

    assert_selector "#{modal} .ac-filter-chip-active[data-autocomplete-filter-value='auditor']", wait: 5
    assert_selector "[data-search-bar-target='input']:focus"
  end

  test "Tab on a highlighted result only moves the focus" do
    visit test_harness_search_bar_path
    count_visits

    dispatch_hotkey("k", ctrl: true)
    assert_selector "[data-search-bar-target='dialog'][open]", wait: 2

    modal = "[data-search-bar-target='dialog']"
    option = "#{modal} [role='option']"
    input = find("[data-search-bar-target='input']")

    # One person, highlighted as it lands. Tab is the only key that goes to the
    # chips, so it is not spent on opening that person.
    input.fill_in with: "ProspectiveNewbie"
    assert_selector "#{option}[aria-selected='true']", count: 1, wait: 5
    input.send_keys(:tab)
    assert_selector "#{modal} .ac-filter-chip:focus"
    assert_selector "#{option}[aria-selected='true']", count: 1
    assert_equal 0, visits, "Tab opened a lone result"

    # Back in the input, the row is still Enter's to open.
    page.send_keys([:shift, :tab])
    assert_selector "[data-search-bar-target='input']:focus"
    page.send_keys(:enter)
    assert_equal 1, visits, "Enter did not open the highlighted result"

    # A fleet vehicle has no owner, and so no page to open. Tab leaves that row
    # alone as well: the text typed is not swapped for the row's value. The key
    # is built by hand, because this list has no chip for a real Tab to land on.
    # A real one takes the focus out of the page, and the browser then keeps it
    # out of every page loaded by the tests that follow.
    input.fill_in with: "!DPW5550"
    assert_selector "#{option}[aria-selected='true']:not([data-autocomplete-url])", count: 1, wait: 5
    page.execute_script(<<~JS)
      document.querySelector("[data-search-bar-target='input']").dispatchEvent(
        new KeyboardEvent("keydown", {key: "Tab", bubbles: true, cancelable: true}))
    JS
    assert_equal "!DPW5550", input.value, "Tab took a row that has no page to open"
  end

  test "Enter or a click on a result with no page to open changes nothing" do
    visit test_harness_search_bar_path

    dispatch_hotkey("k", ctrl: true)
    assert_selector "[data-search-bar-target='dialog'][open]", wait: 2

    option = "[data-search-bar-target='dialog'] [role='option']"
    highlighted = "#{option}[aria-selected='true']:not([data-autocomplete-url])"
    input = find("[data-search-bar-target='input']")

    # A fleet vehicle has no owner, and so no page to open. Typed with Enter in
    # one breath, the Enter waits for the search and is spent on its one row,
    # which is not taken: it lands highlighted, as any lone result does.
    input.send_keys("!DPW5550", :enter)
    assert_selector highlighted, count: 1, wait: 5
    assert_equal "!DPW5550", input.value, "A waiting Enter took a row that has no page to open"

    # Enter on the highlighted row leaves it, and the text, where they are.
    input.send_keys(:enter)
    assert_selector highlighted, count: 1
    assert_equal "!DPW5550", input.value, "Enter took a row that has no page to open"

    # So does a click, which hands the focus back to the input.
    find(option).click
    assert_selector highlighted, count: 1
    assert_equal "!DPW5550", input.value, "A click took a row that has no page to open"
    assert_selector "[data-search-bar-target='input']:focus"
  end

  test "a search that replaces the chips under the focus hands it to the input" do
    visit test_harness_search_bar_path
    page.execute_script(<<~JS)
      document.addEventListener("focusin", (event) => {
        if (event.target.matches(".ac-filter-chip")) window.chipTookFocus = true
      })
    JS

    dispatch_hotkey("k", ctrl: true)
    assert_selector "[data-search-bar-target='dialog'][open]", wait: 2

    modal = "[data-search-bar-target='dialog']"
    input = find("[data-search-bar-target='input']")
    input.fill_in with: "Test"
    assert_selector "#{modal} .ac-filter-chip", minimum: 2, wait: 5

    # One more letter and Tab at once: a chip takes the focus before the search
    # fires, and the search then swaps the chips for its indicator.
    input.send_keys("R", :tab)

    # "TestR" is one person. The search went through and focus is in the input.
    assert_selector "#{modal} [role='option']", count: 1, wait: 5
    assert page.evaluate_script("window.chipTookFocus"), "No chip ever took the focus"
    assert_no_selector "#{modal} .ac-error"
    assert_selector "[data-search-bar-target='input']:focus"
  end

  test "switching to another tab and back leaves the results as they are" do
    visit test_harness_search_bar_path
    page.execute_script("window.addEventListener('blur', () => { window.lostFocus = true })")

    dispatch_hotkey("k", ctrl: true)
    assert_selector "[data-search-bar-target='dialog'][open]", wait: 2

    modal = "[data-search-bar-target='dialog']"
    find("[data-search-bar-target='input']").fill_in with: "Test"
    assert_selector "#{modal} [role='option']", minimum: 2, wait: 5

    # A new tab takes the window's focus, which blurs the input without moving
    # focus off it. Closing the tab hands the focus back.
    open_new_window.close

    assert page.evaluate_script("window.lostFocus"), "The window never lost focus"
    assert_selector "#{modal} [role='option']", minimum: 2
    assert_selector "[data-search-bar-target='input']:focus"
  end

  test "a click on the list that hits no row leaves the focus in the input" do
    visit test_harness_search_bar_path

    dispatch_hotkey("k", ctrl: true)
    assert_selector "[data-search-bar-target='dialog'][open]", wait: 2

    modal = "[data-search-bar-target='dialog']"
    find("[data-search-bar-target='input']").fill_in with: "Test"
    assert_selector "#{modal} [role='option']", minimum: 2, wait: 5

    # A group header is not a result. A click on it used to park the focus on the
    # dialog, with the list still up: Escape then closed the dialog over a list
    # nobody had dismissed, and an Enter waiting for a search still fired.
    first("#{modal} .ac-group-header").click

    assert_selector "[data-search-bar-target='input']:focus"
    assert_selector "#{modal} [role='option']", minimum: 2
  end

  # -------------------------------------------------------------------------
  # Keys pressed before the list has caught up with the text
  # -------------------------------------------------------------------------

  test "Enter pressed while a new search is in flight leaves the previous result alone" do
    visit test_harness_search_bar_path
    count_visits

    dispatch_hotkey("k", ctrl: true)
    assert_selector "[data-search-bar-target='dialog'][open]", wait: 2

    option = "[data-search-bar-target='dialog'] [role='option']"
    input = find("[data-search-bar-target='input']")
    sole = "ProspectiveNewbie"

    # One person, highlighted as it lands.
    input.fill_in with: sole
    assert_selector "#{option}[aria-selected='true']", count: 1, wait: 5

    # Wipe the query, type another and press Enter in one breath. The new
    # search has not even started, so the row on screen, highlight and all,
    # still belongs to the old query.
    input.send_keys(*([:backspace] * sole.length), "Test", :enter)
    assert_equal 0, visits, "Enter opened the previous search's result"

    # The new search finds several people, so the queued Enter opens none of them.
    assert_selector option, minimum: 2, wait: 5
    assert_equal 0, visits, "Enter opened a result once the new search landed"
  end

  test "Enter pressed on text too short to search opens nothing, then or later" do
    visit test_harness_search_bar_path
    count_visits

    dispatch_hotkey("k", ctrl: true)
    assert_selector "[data-search-bar-target='dialog'][open]", wait: 2

    option = "[data-search-bar-target='dialog'] [role='option']"
    input = find("[data-search-bar-target='input']")
    sole = "ProspectiveNewbie"

    # One letter, Enter, and the rest of the callsign in one breath. No search was
    # coming for one letter, so that Enter is not kept for the search that follows:
    # its one result is highlighted, and left for an Enter of its own.
    input.send_keys(sole[0], :enter, sole[1..])
    assert_selector "#{option}[aria-selected='true']", count: 1, wait: 5
    assert_equal 0, visits, "An Enter pressed on one letter opened a later result"

    # Cut the text back to one letter and press Enter at once. The row still up
    # is not for a single letter: it stays unopened, and the list is emptied.
    input.send_keys(*([:backspace] * (sole.length - 1)), :enter)
    assert_equal 0, visits, "Enter opened a result for a one-letter text"
    assert_no_selector option, visible: :all, wait: 5
  end

  test "a search that lands after the text has changed is dropped" do
    visit test_harness_search_bar_path
    count_visits
    sole = "ProspectiveNewbie"

    # The answer to the search for one person is kept back until Enter is pressed,
    # which is how a slow connection delivers it: after the text has moved on.
    page.execute_script(<<~JS, sole)
      const held = arguments[0]
      const realFetch = window.fetch
      window.fetch = (...args) => {
        const response = realFetch(...args)
        if (new URL(String(args[0]), location.href).searchParams.get("q") !== held) return response
        response.then(() => { document.documentElement.dataset.answerHeld = "true" }, () => {})
        return new Promise(resolve => {
          document.addEventListener("keydown", (event) => {
            if (event.key === "Enter") setTimeout(() => resolve(response), 0)
          })
        })
      }
    JS

    dispatch_hotkey("k", ctrl: true)
    assert_selector "[data-search-bar-target='dialog'][open]", wait: 2

    option = "[data-search-bar-target='dialog'] [role='option']"
    input = find("[data-search-bar-target='input']")

    # The search for one person is out, and its answer is waiting at the gate.
    input.fill_in with: sole
    assert_selector "html[data-answer-held='true']", visible: :all, wait: 5

    # The text becomes "Test" and Enter is pressed; only then does the old answer
    # land. It is not for what is typed, so it does not take the Enter.
    input.send_keys(*([:backspace] * sole.length), "Test", :enter)

    assert_selector option, minimum: 2, wait: 5
    assert_equal 0, visits, "The old search's person was opened under the new text"
  end

  test "an Enter still waiting when Escape closes the dialog opens nothing" do
    visit test_harness_search_bar_path
    count_visits

    dispatch_hotkey("k", ctrl: true)
    dialog = "[data-search-bar-target='dialog']"
    assert_selector "#{dialog}[open]", wait: 2

    # One person's callsign, Enter and Escape in one breath. The search has not
    # started, so the Enter is waiting for it when Escape closes the dialog.
    input = find("[data-search-bar-target='input']")
    input.send_keys("ProspectiveNewbie", :enter, :escape)
    assert_no_selector "#{dialog}[open]"

    # The search is called off: nothing is looked up behind the closed dialog.
    wait_out_debounce
    assert_selector "#{dialog} [data-autocomplete-target='results'][hidden]", visible: :all

    # The Enter went with it. With the dialog open again and the callsign typed
    # on, that one person is found and highlighted, and not opened.
    dispatch_hotkey("k", ctrl: true)
    input.send_keys("e")
    assert_selector "#{dialog} [role='option'][aria-selected='true']", count: 1, wait: 5
    assert_equal 0, visits, "The Enter outlived the Escape and opened the result"
  end

  test "an Enter still waiting when a result is clicked opens only that result" do
    visit test_harness_search_bar_path
    count_visits

    dispatch_hotkey("k", ctrl: true)
    assert_selector "[data-search-bar-target='dialog'][open]", wait: 2

    option = "[data-search-bar-target='dialog'] [role='option']"
    input = find("[data-search-bar-target='input']")

    input.fill_in with: "Test"
    assert_selector option, minimum: 2, wait: 5
    slow_searches

    # One person's callsign and Enter, which waits for that search. With the
    # search out, a row of the list still on screen is clicked. The click is the
    # choice: the person the search would find is not opened on top of it.
    input.send_keys(*([:backspace] * 4), "ProspectiveNewbie", :enter)
    assert_selector "html[data-search-started='true']", visible: :all, wait: 5
    first(option).click

    assert_selector "html[data-search-ended='true']", visible: :all, wait: 5
    assert_equal 1, visits, "The clicked row should be the only result opened"
  end

  # Replacing the page under the open dialog disconnects the controller. Chrome
  # blurs an input it removes, and that blur alone dismisses the list; other
  # browsers do not. So in the two tests below the controller is disconnected
  # by hand.

  test "an Enter still waiting when the controller is disconnected opens nothing" do
    visit test_harness_search_bar_path
    count_visits

    dispatch_hotkey("k", ctrl: true)
    option = "[data-search-bar-target='dialog'] [role='option']"
    assert_selector "[data-search-bar-target='dialog'][open]", wait: 2
    input = find("[data-search-bar-target='input']")

    # One person, highlighted as it lands, and still on screen for what follows.
    input.fill_in with: "CustomGender"
    assert_selector "#{option}[aria-selected='true']", count: 1, wait: 5
    slow_searches

    # Another person's callsign and Enter, which waits for that search. The
    # controller goes while the search is out.
    input.send_keys(*([:backspace] * "CustomGender".length), "ProspectiveNewbie", :enter)
    assert_selector "html[data-search-started='true']", visible: :all, wait: 5
    page.execute_script(<<~JS)
      const element = document.querySelector("[data-search-bar-target='dialog'] [data-controller='autocomplete']")
      window.Stimulus.getControllerForElementAndIdentifier(element, "autocomplete").disconnect()
    JS

    # The search is dropped, and its ending does not spend the Enter on the one
    # row left on screen.
    assert_selector "html[data-search-ended='true']", visible: :all, wait: 5
    assert_equal 0, visits, "The Enter outlived the controller and opened a result"
  end

  test "a search still in its debounce when the controller is disconnected never starts" do
    visit test_harness_search_bar_path

    # The controller goes as soon as there is text, inside the debounce.
    page.execute_script(<<~JS)
      document.addEventListener("input", () => setTimeout(() => {
        const element = document.querySelector("[data-search-bar-target='dialog'] [data-controller='autocomplete']")
        window.Stimulus.getControllerForElementAndIdentifier(element, "autocomplete").disconnect()
      }, 0), {once: true})
    JS

    dispatch_hotkey("k", ctrl: true)
    dialog = "[data-search-bar-target='dialog']"
    assert_selector "#{dialog}[open]", wait: 2

    find("[data-search-bar-target='input']").send_keys("Test")
    wait_out_debounce

    # A search that starts puts its "Searching..." bar up at once.
    assert_selector "#{dialog} [data-autocomplete-target='results'][hidden]", visible: :all
  end

  # -------------------------------------------------------------------------
  # Mode switcher gating (hq mode only for HQ Window viewers)
  # -------------------------------------------------------------------------

  test "mode switcher is hidden for an ungated viewer and renders both modes for an HQ viewer" do
    # The signed-in viewer holds no Admin/Shift Management role, so only the
    # person_manage mode exists and the switcher block is not rendered at all.
    visit test_harness_search_bar_path

    dispatch_hotkey("k", ctrl: true)
    assert_selector "[data-search-bar-target='dialog'][open]", wait: 2
    assert_no_selector "[data-search-bar-target='modeInput']", visible: :all

    # Grant the HQ gate (the HQWindowInterfaceEnabled setting defaults on) and
    # reload: both modes render enabled with person_manage still the default.
    ensure_role(Role::SHIFT_MANAGEMENT, "Shift Management")
    grant_role(@person, Role::SHIFT_MANAGEMENT)

    visit test_harness_search_bar_path
    dispatch_hotkey("k", ctrl: true)
    assert_selector "[data-search-bar-target='dialog'][open]", wait: 2

    within "[data-search-bar-target='dialog']" do
      person_input = find("[data-search-bar-target='modeInput'][value='person_manage']", visible: :all)
      hq_input = find("[data-search-bar-target='modeInput'][value='hq']", visible: :all)

      assert person_input.checked?, "person_manage should be the default mode"
      assert_not hq_input.disabled?, "hq must be selectable for an HQ-gated viewer"
      assert_not hq_input.checked?, "hq must not be selected by default"
    end
  end

  test "selected mode persists across reload and drives the live autocomplete mode" do
    visit test_harness_search_bar_path

    dispatch_hotkey("k", ctrl: true)
    assert_selector "[data-search-bar-target='dialog'][open]", wait: 2

    # Default mode is reflected in the live autocomplete attribute and localStorage.
    assert_equal "person_manage", autocomplete_mode_value
    assert_equal "person_manage", page.evaluate_script("window.localStorage.getItem('search-mode')")

    # Even after the page reloads, the persisted (default) mode is restored and
    # pushed into the autocomplete — it never becomes the disabled hq value.
    visit test_harness_search_bar_path
    assert_equal "person_manage", autocomplete_mode_value
  end

  test "a stale hq value in localStorage is rejected back to person_manage" do
    visit test_harness_search_bar_path
    # Simulate a stale/disabled value left by an older build, then reload.
    page.execute_script("window.localStorage.setItem('search-mode', 'hq')")
    visit test_harness_search_bar_path

    # The disabled hq value must not leak into the live autocomplete mode.
    assert_equal "person_manage", autocomplete_mode_value
  end

  test "a legacy account value in localStorage maps to person_manage" do
    visit test_harness_search_bar_path
    page.execute_script("window.localStorage.setItem('search-mode', 'account')")
    visit test_harness_search_bar_path

    assert_equal "person_manage", autocomplete_mode_value
  end

  # -------------------------------------------------------------------------
  # Mode switch re-routes the person already on screen
  # -------------------------------------------------------------------------

  test "switching modes on a person page navigates that person to the new namespace and keeps the modal open" do
    ensure_role(Role::ADMIN, "Admin")
    grant_role(@person, Role::ADMIN)
    target = person(:retired_ranger)

    visit person_path(target)
    dispatch_hotkey("k", ctrl: true)
    assert_selector "[data-search-bar-target='dialog'][open]", wait: 2

    select_mode("timesheet")

    assert_current_path person_timesheets_path(target)
    assert_selector "[data-search-bar-target='dialog'][open]", wait: 2
    assert_equal "timesheet", autocomplete_mode_value

    # ...and back: the same person returns to Person Manage.
    select_mode("person_manage")

    assert_current_path person_path(target)
    assert_selector "[data-search-bar-target='dialog'][open]", wait: 2
  end

  test "switching modes off a person page only changes the search mode" do
    ensure_role(Role::ADMIN, "Admin")
    grant_role(@person, Role::ADMIN)

    visit test_harness_search_bar_path
    dispatch_hotkey("k", ctrl: true)
    assert_selector "[data-search-bar-target='dialog'][open]", wait: 2

    select_mode("swag")

    assert_current_path test_harness_search_bar_path
    assert_equal "swag", autocomplete_mode_value
  end

  # -------------------------------------------------------------------------
  # Result navigation destinations (vehicle / asset)
  # -------------------------------------------------------------------------

  # Live full-stack check: a typed "!"/"#" query hits the real autocomplete
  # endpoint, dispatches to the vehicle/asset adapter, and the rendered row carries
  # the correct click-through destination (data-autocomplete-url). The actual
  # navigation on click/Enter is the shared commit() path verified elsewhere.
  test "vehicle and asset results carry their click-through destination" do
    visit test_harness_search_bar_path
    dispatch_hotkey("k", ctrl: true)
    assert_selector "[data-search-bar-target='dialog'][open]", wait: 2

    # Scope by CSS prefix (no `within`, and re-find fresh each time) to avoid stale
    # element references after the results container re-renders.
    modal = "[data-search-bar-target='dialog']"
    input = "#{modal} input[data-autocomplete-target='input']"

    # "!RANGER1" matches the owned approved vehicle -> owner's vehicle list.
    find(input).set("!RANGER1")
    vehicle_option = "#{modal} [role='option'][data-autocomplete-url*='/vehicles']"
    assert_selector vehicle_option, wait: 3
    assert_equal person_vehicles_path(person(:active_ranger).id),
                 find(vehicle_option)["data-autocomplete-url"]

    # "#RANGER1" matches the current-year asset -> its ops management page.
    find(input).set("#RANGER1")
    asset_option = "#{modal} [role='option'][data-autocomplete-url*='/asset-management/records/']"
    assert_selector asset_option, wait: 3
    assert_equal asset_management_record_path(asset(:radio_current_year).id),
                 find(asset_option)["data-autocomplete-url"]
  end

  # -------------------------------------------------------------------------
  # Dialog polish (backdrop close, focus restore)
  # -------------------------------------------------------------------------

  test "click outside the modal-box closes the modal" do
    visit test_harness_search_bar_path

    dispatch_hotkey("k", ctrl: true)
    assert_selector "[data-search-bar-target='dialog'][open]", wait: 2

    # The dialog element is the box itself, so a click whose target is the
    # dialog -- and not something inside it -- is a click on the backdrop, and
    # that dismisses it.
    page.execute_script(<<~JS)
      const modal = document.querySelector("[data-search-bar-target='dialog']")
      modal.dispatchEvent(new MouseEvent("click", { bubbles: true }))
    JS

    assert_no_selector "[data-search-bar-target='dialog'][open]", wait: 2
  end

  test "clicking inside the modal-box keeps the modal open" do
    visit test_harness_search_bar_path

    dispatch_hotkey("k", ctrl: true)
    assert_selector "[data-search-bar-target='dialog'][open]", wait: 2

    # A click that originates inside the dialog (e.g. the search input) must
    # not close it even though it bubbles up to the dialog's handler.
    find("[data-search-bar-target='input']").click

    assert_selector "[data-search-bar-target='dialog'][open]"
  end

  # Escape from anywhere inside, the focus trap, and the focus restore below
  # are the native <dialog>'s own: there is no handler of ours left to test,
  # and a synthetic keydown has no default action, so they are exercised with
  # real key presses only.

  test "focus returns to the trigger when the modal closes" do
    visit test_harness_search_bar_path

    # Open via the trigger button so it is the previously-focused element.
    trigger = find("[data-action='search-bar#open']")
    trigger.click

    assert_selector "[data-search-bar-target='dialog'][open]", wait: 2
    assert_selector "[data-search-bar-target='input']:focus", wait: 2

    # Close with Escape -- the dialog's own.
    find("[data-search-bar-target='input']").send_keys(:escape)
    assert_no_selector "[data-search-bar-target='dialog'][open]", wait: 2

    # Focus is restored to the trigger button.
    trigger_focused = page.evaluate_script(<<~JS)
      document.activeElement === document.querySelector("[data-action='search-bar#open']")
    JS
    assert trigger_focused, "Focus should return to the trigger button after closing"
  end

  private

  # Current live mode value the autocomplete will send on its next fetch.
  def autocomplete_mode_value
    page.evaluate_script(<<~JS)
      document.querySelector("[data-controller~='autocomplete']")
        ?.getAttribute("data-autocomplete-mode-value")
    JS
  end

  # Pick a mode in the segmented control. The radio is sr-only, so set it and
  # fire the change event the Stimulus action listens for.
  def select_mode(mode)
    page.execute_script(<<~JS, mode)
      const input = document.querySelector(
        `[data-search-bar-target='modeInput'][value='${arguments[0]}']`)
      input.checked = true
      input.dispatchEvent(new Event("change", {bubbles: true}))
    JS
  end

  # Count the results the dialog opens, and stop each visit: the page stays put,
  # so a search still to come can be watched after a result was opened.
  def count_visits
    page.execute_script(<<~JS)
      window.turboVisits = 0
      document.addEventListener("turbo:before-visit", (event) => {
        window.turboVisits++
        event.preventDefault()
      })
    JS
  end

  def visits
    page.evaluate_script("window.turboVisits")
  end

  # Slow every search from here on, so a test can act while one is out, and mark
  # the page when one starts and when one has ended. An aborted one ends at once,
  # as a real request does. Two seconds: a loaded CI runner spent 800ms between
  # finding a row and clicking it, and the answer replaced the row under the click.
  def slow_searches
    page.execute_script(<<~JS)
      const realFetch = window.fetch
      window.fetch = (input, init = {}) => new Promise((resolve, reject) => {
        const timer = setTimeout(() => resolve(realFetch(input, init)), 2000)
        init.signal?.addEventListener("abort", () => { clearTimeout(timer); reject(init.signal.reason) })
      })
      document.addEventListener("autocomplete.loadstart", () => {
        document.documentElement.dataset.searchStarted = "true"
      })
      document.addEventListener("autocomplete.loadend", () => {
        document.documentElement.dataset.searchEnded = "true"
      })
    JS
  end

  # Wait until the debounce the last keys started has run out, so that a search
  # it was going to start has started. The timer is on the page's own clock, set
  # after those keys and for longer than the dialog's 300ms, so it cannot fire first.
  def wait_out_debounce
    page.execute_script(<<~JS)
      delete document.documentElement.dataset.debounceOver
      setTimeout(() => { document.documentElement.dataset.debounceOver = "true" }, 320)
    JS
    assert_selector "html[data-debounce-over='true']", visible: :all
  end

  # Dispatch a keyboard event via JavaScript to avoid Chrome intercepting browser shortcuts
  def dispatch_hotkey(key, ctrl: false, meta: false)
    page.execute_script(<<~JS, key, ctrl, meta)
      const event = new KeyboardEvent("keydown", {
        key: arguments[0],
        ctrlKey: arguments[1],
        metaKey: arguments[2],
        bubbles: true,
        cancelable: true
      })
      document.dispatchEvent(event)
    JS
  end
end
