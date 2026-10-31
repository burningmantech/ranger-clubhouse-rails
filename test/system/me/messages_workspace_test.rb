# frozen_string_literal: true

require "application_system_test_case"

# The Mail Desk in a browser (.scratch/messaging-rework/PRD.md, slice 1): from
# lg a row fills the pane through its frame, below lg a row is a page visit to
# the thread, and review_pane_controller keeps the open thread's row marked.
# Only a browser shows any of it: the frame is enabled by the controller, and
# which column a phone sees is CSS.
class Me::MessagesWorkspaceTest < ApplicationSystemTestCase
  include TimesheetAdminTestHelper # ensure_role / grant_role

  REVIEW_PANE = "[data-controller~=review-pane]"

  # The card a search's hit opened on (common/messages/_thread).
  LANDING = "#messages-thread article[data-landing]"

  # The stepper over a hit's thread (common/messages/_messages_panel).
  STEPPER = "[role=group][aria-label='Matches in this conversation']"

  # A chip in the search field, not the blank one its template holds.
  CHIP = "[data-message-search-target=list] [data-message-search-target=chip]"

  # The landing again, as the page's own scroll-to-element marker runs it.
  REVEAL_AGAIN = <<~JS
    const marker = document.querySelector("#messages-thread [data-controller=scroll-to-element]")
    window.Stimulus.getControllerForElementAndIdentifier(marker, "scroll-to-element").reveal()
  JS

  setup do
    @owner = person(:active_ranger)
    @sender = person(:ranger_with_custom_gender)
    @thread = send_message(@sender, @owner, "Shift swap")
    @other = send_message(@sender, @owner, "Camp tour")
  end

  teardown do
    Current.reset
  end

  test "from lg a row fills the pane in place, and the row keeps its focus and its mark" do
    sign_in(@owner)
    visit me_messages_path
    assert_selector "#navbar-messages a[aria-label='2 unread messages']"
    pane_enabled
    # A page visit replaces <body>, which drops this; a frame visit keeps it.
    page.execute_script("document.querySelector('#{REVIEW_PANE}').dataset.kept = 'yes'")

    find(row(@thread)).click

    assert_selector "aside.review-pane [data-review-id='#{@thread.id}']", text: "Shift swap"
    assert_selector "#{REVIEW_PANE}[data-kept=yes]"
    assert_selector "#{row(@thread)}[aria-current=true]"
    assert_current_path me_message_path(@thread, folder: PersonMessage::FOLDER_INBOX)
    # The reply box does not take focus from the row the reader activated.
    assert_equal @thread.id.to_s, page.evaluate_script("document.activeElement?.dataset?.reviewId")
    # Reading it changed what lies outside the pane too.
    assert_selector "#navbar-messages a[aria-label='1 unread message']"
    assert_no_selector "#{row(@thread)}.messages-conversation-unread"
    assert_selector "#{row(@other)}.messages-conversation-unread"
  end

  # Review finding 12: the label is hidden and Lexxy names its text box from
  # labels alone, so the reply box had no accessible name at all.
  test "the reply box is named Reply" do
    sign_in(@owner)
    visit me_message_path(@thread)

    editor = find("#messages-reply-form lexxy-editor [role=textbox]")
    assert_equal "Reply", editor["aria-label"]
  end

  test "below lg a row opens the thread as its own page" do
    sign_in(@owner)
    on_a_phone do
      visit me_messages_path
      wait_for_controller "review-pane", REVIEW_PANE
      assert_selector "turbo-frame#messages-pane[disabled]", visible: :all

      find(row(@thread)).click

      # Visible text only: a frame visit would have filled the hidden pane.
      assert_selector "aside.review-pane", text: "Shift swap"
      assert_current_path me_message_path(@thread, folder: PersonMessage::FOLDER_INBOX)
      # The thread page's list is a lazy frame in a hidden column: never loaded.
      assert_no_selector "a.review-line", visible: :all
    end
  end

  test "a thread page loads its list with the open row marked, and a folder switch keeps the mark" do
    sign_in(@owner)
    visit me_message_path(@thread)

    assert_selector "#{row(@thread)}[aria-current=true]"

    find("#messages-folder-selector [role=tab]", text: "Archived").click
    assert_no_selector row(@thread)
    find("#messages-folder-selector [role=tab]", text: "Inbox").click

    assert_selector "#{row(@thread)}[aria-current=true]"
    assert_selector "#{row(@other)}:not([aria-current])"
  end

  test "narrowing below lg after a selection shows the open thread, as a load of its address would" do
    sign_in(@owner)
    visit me_messages_path
    pane_enabled
    find(row(@thread)).click
    assert_selector "aside.review-pane [data-review-id='#{@thread.id}']"

    on_a_phone do
      assert_selector "aside.review-pane", text: "Shift swap"
      assert_no_selector row(@thread)
    end
  end

  # Person and HQ never mark a thread read by viewing it, so the open row there
  # is usually unread too: the selected tint must win over the unread one.
  test "on a person's mailbox the open unread row wears the selected tint, not the unread one" do
    manager = person(:echelon_ranger)
    ensure_role(Role::EVENT_MANAGEMENT, "Event Management")
    grant_role(manager, Role::EVENT_MANAGEMENT)
    sign_in(manager)
    visit person_message_path(@owner, @thread)

    assert_selector "#{row(@thread)}[aria-current=true].messages-conversation-unread"
    assert_selector "#{row(@other)}.messages-conversation-unread"
    selected, unselected = [@thread, @other].map do |message|
      page.evaluate_script("getComputedStyle(document.querySelector(#{row(message).to_json})).backgroundColor")
    end
    assert_not_equal unselected, selected, "the selected row must not read as just another unread row"
  end

  # Slice 2. The hits are the person_message fixtures: the full-text index sees
  # no row a test creates.
  test "a search loads the list in place: the tabs give way and the open thread stays" do
    owner = person(:inactive_ranger)
    swap = person_message(:search_dirt_swap)
    sign_in(owner)
    visit me_messages_path
    pane_enabled
    page.execute_script("document.querySelector('#{REVIEW_PANE}').dataset.kept = 'yes'")
    find(row(swap)).click
    assert_selector "aside.review-pane [data-review-id='#{swap.id}']"

    fill_in "Search messages", with: "dirt shift"
    find_field("Search messages").send_keys(:enter)

    assert_selector "[role=status]", text: "2 conversations match “dirt shift” in every folder"
    assert_no_selector "[role=tablist]"
    assert_selector "#{row(swap)}[aria-current=true] mark.search-hit", text: "Dirt"
    assert_selector "aside.review-pane [data-review-id='#{swap.id}']"
    assert_selector "#{REVIEW_PANE}[data-kept=yes]"
    assert_current_path me_messages_path(q: "dirt shift")

    click_on "Clear Search"
    assert_selector "[role=tablist]"
    assert_field "Search messages", with: ""
  end

  # The toggles post what the list shows when they are pressed, from the tab
  # row's frame, not the folder the thread was opened from.
  test "after a folder switch, Mark Read and Mark Unread stream back the folder on screen" do
    sign_in(@owner)
    visit me_messages_path
    pane_enabled
    find(row(@thread)).click # read now: opening a thread on /me reads it
    assert_selector "aside.review-pane [data-review-id='#{@thread.id}']"
    find("#messages-folder-selector [role=tab]", text: "Unread").click
    assert_selector "#messages-folder-selector [role=tab][aria-selected=true]", text: "Unread"
    assert_no_selector row(@thread)

    click_on "Mark Unread"
    assert_selector "#{row(@thread)}[aria-current=true].messages-conversation-unread"
    assert_selector "#messages-folder-selector [role=tab][aria-selected=true]", text: "Unread"
    # The cards morph with the read state, their bubbles' tint included.
    assert_selector "#messages-thread article[data-unread] .bg-warning\\/10 > [data-message-body]"

    click_on "Mark Read"
    assert_selector "#messages-panel-header", text: "Mark Unread"
    assert_no_selector "#messages-thread .bg-warning\\/10"
    assert_no_selector row(@thread)
    assert_selector row(@other)
    assert_selector "#messages-folder-selector [role=tab][aria-selected=true]", text: "Unread"
  end

  test "after a search, a toggle streams back the hits" do
    owner = person(:inactive_ranger)
    swap = person_message(:search_dirt_swap)
    sign_in(owner)
    visit me_messages_path
    pane_enabled
    find(row(swap)).click
    assert_selector "aside.review-pane [data-review-id='#{swap.id}']"
    fill_in "Search messages", with: "dirt shift"
    find_field("Search messages").send_keys(:enter)
    assert_selector "[role=status]", text: "2 conversations match “dirt shift” in every folder"

    click_on "Archive"
    assert_selector "#{row(swap)}[aria-current=true] .badge", text: "Archived"
    assert_selector "[role=status]", text: "2 conversations match “dirt shift” in every folder"
    assert_no_selector "[role=tablist]"
  end

  # Slices 4 and 5 (.scratch/messages-search/PRD.md): suggestions while typing,
  # and a person's chip keeping the search to the conversations they are in.
  test "a person suggested in the search field becomes a chip, and the search keeps to their conversations" do
    radio = person_message(:search_radio_archived)
    swap = person_message(:search_dirt_swap)
    sign_in(person(:inactive_ranger))
    visit me_messages_path

    fill_in "Search messages", with: "ran"
    assert_selector "[role=option][aria-selected=true]", text: "Search messages for “ran”"
    # The search's own row has no header over it and is in no group; the people have theirs.
    assert_selector ".ac-group-header", count: 1
    assert_no_selector "[role=group] [role=option]", text: "Search messages"
    find("[role=group][aria-label='#{MessagesConcern::SUGGESTED_PEOPLE}'] [role=option]", text: "RANGER1").click

    assert_selector CHIP, text: "RANGER1"
    assert_field "Search messages", with: ""
    assert_selector "[role=status]", text: "2 conversations with RANGER1 in every folder"

    # Review finding: a person the field holds as a chip was suggested again.
    fill_in "Search messages", with: "ran"
    assert_selector "[role=option]", text: "Search messages for “ran”"
    assert_no_selector "[role=option]", text: "RANGER1"

    fill_in "Search messages", with: "dirt"
    find_field("Search messages").send_keys(:enter)
    assert_selector "[role=status]", text: "1 conversation with RANGER1 matches “dirt” in every folder"
    assert_selector row(radio)
    assert_no_selector row(swap)

    find("button[aria-label='Remove RANGER1']").click
    assert_selector "[role=status]", text: "2 conversations match “dirt” in every folder"
    assert_selector row(swap)
    assert_no_selector CHIP
  end

  test "Enter searches for the text, the suggestions up or still to come, and a person arrowed to is taken as a chip" do
    sign_in(person(:inactive_ranger))
    visit me_messages_path

    # Before the suggestions come: a person among them must not hold the Enter,
    # and the search for them still in its debounce never starts.
    count_searches_after_enter
    fill_in "Search messages", with: "ran"
    find_field("Search messages").send_keys(:enter)
    assert_selector "[role=status]", text: "2 conversations match “ran” in every folder"
    wait_out_debounce
    assert_equal 0, page.evaluate_script("window.searchesAfterEnter"), "The suggestions were fetched after the Enter"
    assert_no_selector "[role=option]"

    fill_in "Search messages", with: "rang"
    assert_selector "[role=option]", text: "RANGER1"
    find_field("Search messages").send_keys(:enter)
    assert_selector "[role=status]", text: "2 conversations match “rang” in every folder"
    assert_no_selector "[role=option]"
    assert_no_selector CHIP

    fill_in "Search messages", with: "ran"
    assert_selector "[role=option]", text: "RANGER1"
    find_field("Search messages").send_keys(:down, :enter)
    assert_selector CHIP, text: "RANGER1"
    assert_selector "[role=status]", text: "2 conversations with RANGER1 in every folder"
  end

  # Review finding: Tab dropped a person the reader had arrowed to.
  test "Tab takes a person arrowed to as a chip, and leaves the text's own row as it leaves the text" do
    sign_in(person(:inactive_ranger))
    visit me_messages_path

    fill_in "Search messages", with: "rang"
    assert_selector "[role=option][aria-selected=true]", text: "Search messages for “rang”"
    find_field("Search messages").send_keys(:tab)
    assert_no_selector "[role=option]"
    assert_field "Search messages", with: "rang"
    assert_no_selector CHIP

    fill_in "Search messages", with: "ran"
    assert_selector "[role=option]", text: "RANGER1"
    find_field("Search messages").send_keys(:down, :tab)
    assert_selector CHIP, text: "RANGER1"
    assert_selector "[role=status]", text: "2 conversations with RANGER1 in every folder"
  end

  # The chips sit outside the list's frame and change before the search they
  # run is sent: one that fails puts back the chips the list still answers to.
  test "a chip removed for a search that fails comes back, over the list it answers to" do
    sign_in(person(:inactive_ranger))
    visit me_messages_path(with: ["RANGER1"])
    assert_selector CHIP, text: "RANGER1"
    assert_selector "[role=status]", text: "with RANGER1"
    wait_for_controller "message-search", "form#messages-search"

    page.driver.browser.execute_cdp("Network.enable")
    page.driver.browser.execute_cdp("Network.setBlockedURLs", urls: ["*/me/messages?*"])
    find("#{CHIP} button[aria-label='Remove RANGER1']").click
    assert_selector CHIP, text: "RANGER1"
    assert_selector "[role=status]", text: "with RANGER1"
    assert_selector "#{CHIP} input[type=hidden][name='with[]'][value=RANGER1]", visible: :all
  ensure
    page.driver.browser.execute_cdp("Network.disable")
  end

  # The text too, which taking a person turns into the chip: the field goes
  # back to the search the list answers to (message_search_controller).
  test "a person taken for a search that fails leaves the field as the list answers to it" do
    sign_in(person(:inactive_ranger))
    visit me_messages_path(q: "ran")
    assert_selector "[role=status]", text: "match “ran”"
    wait_for_controller "message-search", "form#messages-search"
    fill_in "Search messages", with: "ran"
    assert_selector "[role=option]", text: "RANGER1"

    page.driver.browser.execute_cdp("Network.enable")
    page.driver.browser.execute_cdp("Network.setBlockedURLs", urls: ["*/me/messages?*"])
    page.execute_script(<<~JS)
      document.addEventListener("turbo:submit-end", ({detail}) => { document.documentElement.dataset.searched = detail.success }, {once: true})
    JS
    find("[role=option]", text: "RANGER1").click
    assert_selector "html[data-searched=false]", visible: :all
    assert_field "Search messages", with: "ran"
    assert_no_selector CHIP
    assert_selector "[role=status]", text: "match “ran”"
  ensure
    page.driver.browser.execute_cdp("Network.disable")
  end

  # Shared with compose (callsign_chips_controller#addChip): nothing goes until
  # the max is reached, then the oldest. Compose takes one chip and the search
  # three, so the max is set higher here, where the sum once went wrong.
  test "a chip past the max replaces the oldest, and none goes before it" do
    sign_in(@owner)
    visit me_messages_path
    wait_for_controller "message-search", "form#messages-search"
    add_chips = lambda do |*callsigns|
      page.execute_script(<<~JS)
        const form = document.querySelector("form#messages-search")
        form.dataset.messageSearchMaxValue = "4"
        const chips = window.Stimulus.getControllerForElementAndIdentifier(form, "message-search");
        #{callsigns.to_json}.forEach((callsign) => chips.addChip(callsign))
      JS
    end

    add_chips.call("One", "Two", "Three", "Four")
    assert_equal %w[One Two Three Four], all(CHIP).map(&:text)
    add_chips.call("Five")
    assert_equal %w[Two Three Four Five], all(CHIP).map(&:text)
  end

  # Review finding: Back restored the chips a search had just set, over the
  # list from before it. Turbo keeps the page as the search's answer arrives,
  # with the field showing that search; restored, the field goes back to its
  # own address, so Back is the kept page, not a fetch.
  test "Back from a search shows the mailbox as it was, without the search's chips or text" do
    sign_in(person(:inactive_ranger))
    visit me_messages_path(q: "dirt")
    assert_selector "[role=status]", text: "match “dirt”"
    page.execute_script("document.body.dataset.kept = 'yes'")

    fill_in "Search messages", with: "ran"
    page.execute_script(<<~JS)
      document.addEventListener("turbo:load", () => { document.documentElement.dataset.searchVisited = "true" }, {once: true})
    JS
    find("[role=option]", text: "RANGER1").click
    assert_selector "[role=status]", text: "2 conversations with RANGER1 in every folder"
    # The list's frame renders, then makes a page visit of its own for the
    # address (turbo:load): one starting after a Back would cancel Back's.
    assert_selector "html[data-search-visited]", visible: :all

    go_back
    assert_selector "[role=status]", text: "match “dirt”"
    assert_selector "body[data-kept=yes]" # the kept page, once it shows
    assert_field "Search messages", with: "dirt"
    assert_no_selector CHIP
  end

  # The iPad check: Clear Search goes to the bare mailbox path, the page it is on,
  # so active_links_controller marked it current, pressed and read as the current
  # page, on every whole load of a search: Back, a reload, a link.
  test "Clear Search is never marked as the current page" do
    sign_in(person(:inactive_ranger))
    visit me_messages_path(q: "dirt")
    wait_for_controller "active-links", "body"

    assert_selector "a", text: "Clear Search"
    assert_no_selector "a[aria-current=true]", text: "Clear Search"
  end

  # The iPad check: with a keyboard up, the suggestions open above the field, and
  # never under the sticky navbar, since the page scrolls inside .drawer-content,
  # which clips what reaches past its top.
  test "suggestions above the field stay under the navbar" do
    sign_in(person(:inactive_ranger))
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 1280, height: 420,
                                                                           deviceScaleFactor: 1, mobile: false)
    visit me_messages_path
    # The field 180px down the window, a keyboard over all from 40px under it.
    page.execute_script(<<~JS)
      const field = document.querySelector("form#messages-search input[name=q]")
      document.querySelector(".drawer-content").scrollTop += field.getBoundingClientRect().top - 180
      const bottom = field.getBoundingClientRect().bottom + 40
      Object.defineProperty(window, "visualViewport", {configurable: true, value: {offsetTop: 0, pageTop: 0, height: bottom}})
    JS

    fill_in "Search messages", with: "ran"
    assert_selector "[role=option]", text: "RANGER1"
    list, scroller = page.evaluate_script(<<~JS)
      [document.querySelector("form#messages-search [role=listbox]").getBoundingClientRect().toJSON(),
       document.querySelector(".drawer-content").getBoundingClientRect().toJSON()]
    JS
    assert_operator list["bottom"], :<=, 180, "The list went below the field, under the keyboard"
    assert_operator list["top"], :>=, scroller["top"], "The list ran under the navbar"
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  # Review finding: the room above was measured from the text, but the list
  # hangs from the box around the chips, so a chip that wrapped the text to a
  # second line put the list's first rows under the navbar. Where there is less
  # room than its floor, the list takes what there is.
  test "suggestions above a field whose chips wrap its text stay under the navbar" do
    sign_in(person(:inactive_ranger))
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 1024, height: 420,
                                                                           deviceScaleFactor: 1, mobile: false)
    visit me_messages_path(with: ["RetiredRanger"])
    assert_selector CHIP, text: "RetiredRanger"
    # The text on a line of its own, 180px down the window, a keyboard over all from 40px under it.
    page.execute_script(<<~JS)
      const field = document.querySelector("form#messages-search input[name=q]")
      document.querySelector(".drawer-content").scrollTop += field.getBoundingClientRect().top - 180
      const bottom = field.getBoundingClientRect().bottom + 40
      Object.defineProperty(window, "visualViewport", {configurable: true, value: {offsetTop: 0, pageTop: 0, height: bottom}})
    JS
    assert_operator page.evaluate_script(<<~JS), :>, 30, "The chip never wrapped the text"
      document.querySelector("form#messages-search input[name=q]").getBoundingClientRect().top -
        document.querySelector("form#messages-search [data-message-search-target=list]").parentElement.getBoundingClientRect().top
    JS

    fill_in "Search messages", with: "ran"
    assert_selector "[role=option]", text: "RANGER1"
    list, box, scroller = page.evaluate_script(<<~JS)
      [document.querySelector("form#messages-search [role=listbox]").getBoundingClientRect().toJSON(),
       document.querySelector("form#messages-search [data-message-search-target=list]").parentElement.getBoundingClientRect().toJSON(),
       document.querySelector(".drawer-content").getBoundingClientRect().toJSON()]
    JS
    assert_operator list["bottom"], :<=, box["top"], "The list went below the box"
    assert_operator list["top"], :>=, scroller["top"], "The list ran under the navbar"
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  # Review finding: the "Searching…" row kept its place after the chips but took
  # the whole box's width, so it ran past the box, and on a phone made the page
  # scroll sideways while a search was out.
  test "the searching row keeps within the search box" do
    sign_in(person(:inactive_ranger))
    on_a_phone do
      visit me_messages_path(with: ["RetiredRanger"])
      assert_selector CHIP, text: "RetiredRanger"
      wait_for_controller "autocomplete", "#messages-search-autocomplete"
      row, box, scroller = page.evaluate_script(<<~JS)
        (() => {
          const component = document.getElementById("messages-search-autocomplete")
          window.Stimulus.getControllerForElementAndIdentifier(component, "autocomplete").showLoading()
          const box = document.querySelector("form#messages-search [data-message-search-target=list]").parentElement
          const scroller = document.querySelector(".drawer-content")
          return [component.querySelector("[data-autocomplete-target=loading]").getBoundingClientRect().toJSON(),
                  box.getBoundingClientRect().toJSON(), {scrollWidth: scroller.scrollWidth, clientWidth: scroller.clientWidth}]
        })()
      JS
      assert_in_delta box["left"], row["left"], 1.5, "The row did not start at the box"
      assert_operator row["right"], :<=, box["right"] + 1, "The row ran past the box"
      assert_equal scroller["clientWidth"], scroller["scrollWidth"], "The page scrolls sideways"
    end
  end

  # Review finding: a press on the box beside the text focused nothing, and closed an open list.
  test "a press anywhere in the search box puts the caret in the text, and an open list stays" do
    sign_in(person(:inactive_ranger))
    visit me_messages_path
    icon = find("form#messages-search .fa-magnifying-glass")

    icon.click
    assert_selector "form#messages-search input[name=q]:focus"

    find_field("Search messages").send_keys("ran")
    assert_selector "[role=option]", text: "RANGER1"
    icon.click
    assert_selector "form#messages-search input[name=q]:focus"
    assert_selector "[role=option]", text: "RANGER1"
  end

  # Review finding: beside a chip the list was as narrow as the text after it,
  # and a long row pushed it sideways rather than being cut short.
  test "the suggestions hang under the whole search box, and a long row is cut short" do
    sign_in(person(:inactive_ranger))
    on_a_phone do
      visit me_messages_path(with: ["RetiredRanger"])
      assert_selector CHIP, text: "RetiredRanger"
      fill_in "Search messages", with: "radio handoff at the outpost by the gate after the burn"
      assert_selector "[role=option]", text: "Search messages for"

      edges = page.evaluate_script(<<~JS)
        (() => {
          const box = document.querySelector("[data-message-search-target=list]").parentElement.getBoundingClientRect()
          const list = document.querySelector("form#messages-search [role=listbox]")
          const rect = list.getBoundingClientRect()
          return [rect.left - box.left, box.right - rect.right, list.scrollWidth - list.clientWidth]
        })()
      JS
      left, right, overflow = edges
      assert_in_delta 0, left, 2, "The list starts where the box does"
      assert_in_delta 0, right, 2, "The list ends where the box does"
      assert_equal 0, overflow, "A row ran past the list"
    end
  end

  # Review finding: the first row's highlight scrolled it into view, which
  # moved the page when the list sat above the field and reached past its top.
  test "the first suggestion arrives highlighted without scrolling anything, and the arrow keys still bring a row into view" do
    sign_in(person(:inactive_ranger))
    visit me_messages_path
    page.execute_script(<<~JS)
      window.scrolledIntoView = 0
      const scrollIntoView = Element.prototype.scrollIntoView
      Element.prototype.scrollIntoView = function (...args) {
        window.scrolledIntoView++
        return scrollIntoView.apply(this, args)
      }
    JS

    fill_in "Search messages", with: "ran"
    assert_selector "[role=option]", text: "RANGER1"
    assert_selector "[role=option][aria-selected=true]", text: "Search messages for “ran”"
    assert_equal 0, page.evaluate_script("window.scrolledIntoView")

    find_field("Search messages").send_keys(:down)
    assert_selector "[role=option][aria-selected=true]", text: "RANGER1"
    assert_equal 1, page.evaluate_script("window.scrolledIntoView")
  end

  # A hit opens its thread at the first message holding a match
  # (.scratch/messages-search/PRD.md, slice 1). From lg the pane scrolls itself
  # there and the page under it stays put, keeping the list where the reader
  # left it; below lg the thread is the page, and the page scrolls. Visited by
  # address: the full-text index never sees the replies a test creates.
  test "a hit's thread opens at its match, scrolling the pane from lg and never the page under it" do
    long_thread
    sign_in(@owner)

    visit me_message_path(@thread, q: "thermos")
    assert_selector LANDING, text: "Bring the thermos."
    assert_eventually("the pane never brought the match to its top") { landed_below?(LANDING, "aside.review-pane") }
    assert_equal 0, drawer_scroll_top

    on_a_phone do
      visit me_message_path(@thread, q: "thermos")
      assert_selector LANDING, text: "Bring the thermos."
      assert_eventually("the page never brought the match to its top") { landed_below?(LANDING, ".drawer-content") }
    end
  end

  # The top message is on screen as its thread opens: landing on it moves
  # nothing, so the header above it -- the party, the subject, the toggles,
  # and on a phone the hero's back link -- stays in view.
  test "a hit on the thread's top message moves nothing" do
    top = send_message(@sender, @owner, "Gate", body: "Who brings the thermos?")
    long_thread(top, word_at: nil)
    marker = "#messages-thread [data-controller=scroll-to-element]"
    sign_in(@owner)

    visit me_message_path(top, q: "thermos")
    assert_selector LANDING, text: "Who brings the thermos?"
    wait_for_controller "scroll-to-element", marker
    assert_equal 0, page.evaluate_script("document.querySelector('aside.review-pane').scrollTop")

    on_a_phone do
      visit me_message_path(top, q: "thermos")
      assert_selector LANDING, text: "Who brings the thermos?"
      wait_for_controller "scroll-to-element", marker
      assert_equal 0, drawer_scroll_top
    end
  end

  # The HQ shell zooms itself on a wide shared display (components/hq-window.css):
  # what is drawn is measured zoomed, but the pane scrolls in its own pixels.
  test "a hit lands on its match under a CSS zoom" do
    long_thread
    sign_in(@owner)
    visit me_message_path(@thread, q: "thermos")
    assert_selector LANDING, text: "Bring the thermos."
    assert_eventually("the pane never landed") { landed_below?(LANDING, "aside.review-pane") }

    page.execute_script(<<~JS)
      document.querySelector(".messages-workspace").style.zoom = "1.15"
      document.querySelector("aside.review-pane").scrollTop = 0
      #{REVEAL_AGAIN}
    JS
    # scroll-mt-18's 72px and the pane's 1px border, drawn 15% larger.
    assert_eventually("the zoomed pane missed the match") { landed_below?(LANDING, "aside.review-pane", at: 82.95) }
  end

  # The pane keeps its scroll through a frame's swap, so the next thread opened
  # in it began a long way down, where the last search's landing had left it.
  test "the pane opens each thread at its top" do
    long_thread
    long_thread(@other, word_at: nil)
    sign_in(@owner)
    visit me_messages_path
    pane_enabled
    page.execute_script("document.querySelector('turbo-frame#messages-pane').src = #{me_message_path(@thread, q: "thermos").to_json}")
    assert_eventually("the pane never landed") { landed_below?(LANDING, "aside.review-pane") }

    find(row(@other)).click
    assert_selector "aside.review-pane [data-review-id='#{@other.id}']"
    assert_eventually("the pane kept the last thread's scroll") do
      page.evaluate_script("document.querySelector('aside.review-pane').scrollTop").zero?
    end
  end

  # A pane off screen -- stacked under the list in the HQ window, or starting
  # too low for its foot to show -- scrolls to the match, and then the page
  # moves just as far as it takes to show it.
  test "a hit in a pane off screen brings the page to the match" do
    long_thread
    sign_in(@owner)
    visit me_message_path(@thread, q: "thermos")
    assert_eventually("the pane never landed") { landed_below?(LANDING, "aside.review-pane") }

    page.execute_script(<<~JS)
      document.querySelector(".messages-workspace").insertAdjacentHTML("beforebegin", '<div style="height: 1600px"></div>')
      document.querySelector("aside.review-pane").scrollTop = 0
      #{REVEAL_AGAIN}
    JS
    assert_eventually("the match never came on screen") { on_screen?(LANDING) }
    assert_operator drawer_scroll_top, :>, 0
  end

  # The stepper over a hit's thread (.scratch/messages-search/PRD.md, slice 2,
  # as ruled 2026-10-30): one stop per message holding a match, round past
  # either end, the ring going with it. It stays pinned in reach as the pane --
  # or below lg the page -- scrolls under it, and a message it brings to the top
  # stops clear of it. The last match sits too near the thread's foot to reach
  # the top: it shows wherever the pane's end leaves it, still under the stepper.
  test "the stepper walks a hit's matches a message at a time, round past either end, and stays in reach" do
    long_thread(word_at: [3, 10, 17])
    sign_in(@owner)
    visit me_message_path(@thread, q: "thermos")
    assert_selector STEPPER, text: "Match 1 of 3"
    assert_selector LANDING, text: "(3)"

    [["next", "Match 2 of 3", "(10)", true], ["next", "Match 3 of 3", "(17)", false],
     ["next", "Match 1 of 3", "(3)", true], ["previous", "Match 3 of 3", "(17)", false]].each do |direction, count, body, at_top|
      step_match(direction)
      assert_selector STEPPER, text: count
      assert_selector LANDING, text: body
      assert_selector "#messages-thread article[data-landing]", count: 1
      # At once, and clear of the stepper.
      assert in_view_under_stepper?(LANDING, "aside.review-pane"), "#{body} never came into the pane's view, clear of the stepper"
      assert landed_below?(LANDING, "aside.review-pane"), "the pane never brought #{body} to its top" if at_top
      assert_equal 24, pinned_below(STEPPER, "aside.review-pane").round, "the stepper left the top of the pane"
    end
    assert_equal 0, drawer_scroll_top

    on_a_phone do
      visit me_message_path(@thread, q: "thermos")
      assert_selector STEPPER, text: "Match 1 of 3"
      assert_eventually("the page never brought the match to its top") { landed_below?(LANDING, ".drawer-content") }
      step_match("next")
      assert_selector LANDING, text: "(10)"
      # At once: a second step taken while a smooth scroll still ran would find
      # its card passing through the screen and leave it where that scroll ended.
      assert landed_below?(LANDING, ".drawer-content"), "the page never brought the match to its top at once"
      assert in_view_under_stepper?(LANDING, ".drawer-content"), "the match sits under the stepper"
      assert_operator pinned_below(STEPPER, ".drawer-content"), :<, 56, "the stepper scrolled away with the page"
    end
  end

  # A match the reader scrolled under the stepper, or into the room its card
  # keeps for it (scroll-mt-18), is on screen but not in view: a step to it
  # scrolls it clear.
  test "a step to a match under the stepper scrolls it clear" do
    long_thread(word_at: [3, 10, 17])
    sign_in(@owner)
    visit me_message_path(@thread, q: "thermos")
    assert_selector STEPPER, text: "Match 1 of 3"
    wait_for_controller "scroll-to-element", "#messages-thread [data-controller=scroll-to-element]"

    page.execute_script(<<~JS)
      const pane = document.querySelector("aside.review-pane")
      const card = [...document.querySelectorAll("#messages-thread article")].find((card) => card.textContent.includes("(10)"))
      pane.scrollTop += card.getBoundingClientRect().top - pane.getBoundingClientRect().top - pane.clientTop - 30
    JS
    step_match("next")
    assert_selector LANDING, text: "(10)"
    assert landed_below?(LANDING, "aside.review-pane"), "the step left the match under the stepper"
  end

  # A match taller than the pane is never wholly on screen. Its first arrival
  # may bring the pane's foot on screen, as any match's may; after that, steps
  # to it scroll the pane alone, never the page under it, which carried the
  # list a little further from the open row at each arrival.
  test "a step to a match taller than the pane leaves the page where it is" do
    long_thread(word_at: [3, 17])
    send_message(@sender, @owner, @thread.subject, body: ["Bring the thermos. (20)", *["More."] * 80].join("\n"), reply_to: @thread)
    sign_in(@owner)
    visit me_message_path(@thread, q: "thermos")
    assert_selector STEPPER, text: "Match 1 of 3"

    step_match("previous")
    assert_selector LANDING, text: "(20)"
    assert landed_below?(LANDING, "aside.review-pane"), "the pane never brought the tall match to its top"
    settled = drawer_scroll_top
    %w[(3) (17) (20)].each do |body|
      step_match("next")
      assert_selector LANDING, text: body
      assert landed_below?(LANDING, "aside.review-pane"), "the pane never brought #{body} to its top" if body == "(20)"
      assert_equal settled, drawer_scroll_top, "the step to #{body} moved the page"
    end
  end

  # A morphing refresh -- a form redirecting back to the page, as the HQ
  # banner's do -- draws the stepper at the match the thread opened on, while
  # review_pane_controller keeps the ring where the reader stepped it: the
  # count and the landing go with the ring.
  test "a morphing refresh leaves the stepper at the match the reader stepped to" do
    long_thread(word_at: [3, 10, 17])
    sign_in(@owner)
    visit me_message_path(@thread, q: "thermos")
    assert_selector STEPPER, text: "Match 1 of 3"
    step_match("next")
    assert_selector LANDING, text: "(10)"

    page.execute_script(<<~JS)
      document.addEventListener("turbo:morph", () => { document.documentElement.dataset.morphed = "yes" }, {once: true})
      Turbo.visit(location.href, {action: "replace"})
    JS
    assert_selector "html[data-morphed=yes]"
    assert_selector STEPPER, text: "Match 2 of 3"
    assert_selector "#messages-thread article[data-landing]", count: 1
    assert_selector LANDING, text: "(10)"
    assert landed_below?(LANDING, "aside.review-pane"), "the refresh took the pane to another match"
  end

  # The cards' read-state morphs draw no search (MessagesConcern#card_streams):
  # the page keeps the marks and the ring _thread drew.
  test "Mark Unread and Mark Read leave the search's marks and ring as drawn" do
    long_thread
    sign_in(@owner)
    visit me_message_path(@thread, q: "thermos")
    assert_selector "#{LANDING} mark.search-hit", text: "thermos"

    click_on "Mark Unread"
    assert_selector "#messages-thread article[data-unread]"
    assert_selector "#{LANDING} mark.search-hit", text: "thermos"
    click_on "Mark Read"
    assert_no_selector "#messages-thread article[data-unread]"
    assert_selector "#{LANDING} mark.search-hit", text: "thermos"
    assert_selector "#messages-thread article[data-landing]", count: 1
  end

  private

  # Twenty replies in +thread+, those at +word_at+ alone saying "thermos",
  # each with its place: matches far below the top of a pane that scrolls.
  def long_thread(thread = @thread, word_at: 10)
    20.times do |index|
      body = Array(word_at).include?(index) ? "Bring the thermos. (#{index})" : (["Reply #{index}."] * 6).join("\n")
      send_message(@sender, @owner, thread.subject, body:, reply_to: thread)
    end
  end

  def step_match(direction)
    find("#{STEPPER} button[aria-label='#{direction.capitalize} match']").click
  end

  # The card is wholly in +scroller+'s view and on screen, clear of the
  # stepper: the gap its scroll margin leaves, 12px or more, less a pixel for
  # the scroll's rounding.
  def in_view_under_stepper?(card, scroller)
    page.evaluate_script(<<~JS)
      (() => {
        const card = document.querySelector(#{card.to_json}).getBoundingClientRect()
        const view = document.querySelector(#{scroller.to_json}).getBoundingClientRect()
        const stepper = document.querySelector(#{STEPPER.to_json}).getBoundingClientRect()
        return card.top - stepper.bottom >= 11 && card.bottom <= Math.min(view.bottom, window.innerHeight)
      })()
    JS
  end

  # How far +element+ sits below the top of +scroller+'s view: a pinned stepper
  # stays there, whatever the scroll.
  def pinned_below(element, scroller)
    page.evaluate_script(<<~JS)
      (() => {
        const scroller = document.querySelector(#{scroller.to_json})
        return document.querySelector(#{element.to_json}).getBoundingClientRect().top -
          scroller.getBoundingClientRect().top - scroller.clientTop
      })()
    JS
  end

  # The card sits +at+ pixels -- scroll-mt-18's 72, clear of the stepper
  # pinned over the cards -- below the top of the scroller's view; false while
  # it is not on the page yet.
  def landed_below?(card, scroller, at: 72)
    page.evaluate_script(<<~JS)&.between?(at - 1.2, at + 1.2)
      (() => {
        const card = document.querySelector(#{card.to_json})
        const scroller = document.querySelector(#{scroller.to_json})
        if (!card || !scroller) return null
        return card.getBoundingClientRect().top - scroller.getBoundingClientRect().top - scroller.clientTop
      })()
    JS
  end

  def on_screen?(selector)
    page.evaluate_script(<<~JS)
      (() => {
        const {top, bottom} = document.querySelector(#{selector.to_json}).getBoundingClientRect()
        return top >= 0 && bottom <= window.innerHeight
      })()
    JS
  end

  def drawer_scroll_top = page.evaluate_script("document.querySelector('.drawer-content').scrollTop")

  # Count the autocomplete searches that start after an Enter, from here on.
  def count_searches_after_enter
    page.execute_script(<<~JS)
      window.searchesAfterEnter = 0
      let entered = false
      document.addEventListener("keydown", (event) => { if (event.key === "Enter") entered = true }, true)
      document.addEventListener("autocomplete.loadstart", () => { if (entered) window.searchesAfterEnter++ })
    JS
  end

  def row(message)
    "a.review-line[data-review-id='#{message.id}']"
  end

  # The controller enables the frame from lg up; before that a click is a page visit.
  def pane_enabled
    wait_for_controller "review-pane", REVIEW_PANE
    assert_selector "turbo-frame#messages-pane:not([disabled])", visible: :all
  end

  def send_message(sender, recipient, subject, body: "#{subject}, please.", reply_to: nil)
    PersonMessage.create!(message_type: PersonMessage::MESSAGE_TYPE_CONTACT, person: recipient,
                          creator_person: sender, sender_person: sender,
                          sender_type: PersonMessage::SENDER_TYPE_PERSON, subject:, body:, reply_to:)
  end
end
