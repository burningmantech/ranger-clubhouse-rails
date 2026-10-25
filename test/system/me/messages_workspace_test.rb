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

    click_on "Mark Read"
    assert_selector "#messages-panel-header", text: "Mark Unread"
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

  private

  def row(message)
    "a.review-line[data-review-id='#{message.id}']"
  end

  # The controller enables the frame from lg up; before that a click is a page visit.
  def pane_enabled
    wait_for_controller "review-pane", REVIEW_PANE
    assert_selector "turbo-frame#messages-pane:not([disabled])", visible: :all
  end

  def send_message(sender, recipient, subject)
    PersonMessage.create!(message_type: PersonMessage::MESSAGE_TYPE_CONTACT, person: recipient,
                          creator_person: sender, sender_person: sender,
                          sender_type: PersonMessage::SENDER_TYPE_PERSON, subject:, body: "#{subject}, please.")
  end
end
