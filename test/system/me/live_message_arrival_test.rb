# frozen_string_literal: true

require "application_system_test_case"

# End to end: a browser open on a page sees a message arrive, through the cable
# connection, the stream the layout subscribes to, PersonMessage's after-commit
# broadcast and the replace of #navbar-messages.
#
# Tests run Action Cable on its test adapter, which records broadcasts and
# delivers none, so this swaps in the in-process async adapter, the way
# ActionCable::TestHelper swaps in the test one. Capybara's server runs in this
# process, so a broadcast made here reaches the browser.
class Me::LiveMessageArrivalTest < ApplicationSystemTestCase
  include RichTextEditorTestHelper

  setup do
    @ranger = person(:active_ranger)
    @sender = person(:ranger_with_custom_gender)
    @cable = ActionCable.server
    @recorded = @cable.pubsub
    @cable.instance_variable_set(:@pubsub, ActionCable::SubscriptionAdapter::Async.new(@cable))
  end

  teardown do
    @cable.pubsub.shutdown
    @cable.instance_variable_set(:@pubsub, @recorded)
  end

  test "a new message puts the envelope on the recipient's navbar without a reload" do
    ranger = person(:active_ranger)
    sender = person(:ranger_with_custom_gender)
    sign_in(ranger)
    visit me_root_path

    assert_selector "#navbar-messages[hidden]", visible: :hidden
    # Subscribed: Turbo marks the source once the channel confirms.
    assert_selector "turbo-cable-stream-source[connected]", visible: :all

    PersonMessage.create!(person: ranger, sender_person: sender, creator_person: sender,
                          sender_type: PersonMessage::SENDER_TYPE_PERSON,
                          subject: "Shift swap", body: "Thursday?")

    # By label: the link has no text, and Capybara's link locator does not read aria-label.
    assert_css "#navbar-messages a[aria-label='1 unread message'][href='#{me_messages_path(folder: PersonMessage::FOLDER_UNREAD)}']"
    assert_selector "#live-region", text: "#{sender.callsign} sent you a message.", visible: :all
  end

  # Slice 5 of the messaging rework: a reply lands in the open thread, and on
  # the owner's own page, on screen, it is read there (ruling D6).
  test "a reply lands in the open thread and is read there, the envelope count dropping back" do
    deliver("Camp tour") # stays unread throughout
    open_thread
    assert_css "#navbar-messages a[aria-label='1 unread message']"

    reply = deliver(reply_to: @thread)

    card = "#messages-thread article##{ActionView::RecordIdentifier.dom_id(reply, :card)}"
    assert_selector card, text: "On my way"
    # It posts what the list beside the pane shows, from the tab row's fields.
    assert_equal [mark_read_me_message_path(@thread)], mark_read_posts
    assert_equal [{ "folder" => PersonMessage::FOLDER_INBOX }], mark_read_bodies
    # Read where it landed: its New chip goes, and the envelope that went up for
    # it comes back down to the other thread.
    assert_no_selector "#{card}[data-unread]"
    assert_css "#navbar-messages a[aria-label='1 unread message']"
    assert_equal ["2 unread messages", "1 unread message"], page.evaluate_script("window.envelopes")
    assert reply.reload.read?(@ranger.id)
  end

  test "a reply that lands while the page is hidden stays New" do
    open_thread
    page.execute_script("Object.defineProperty(document, 'visibilityState', { value: 'hidden', configurable: true })")

    reply = deliver(reply_to: @thread)

    assert_selector "#messages-thread article[data-unread]", text: "On my way"
    assert_empty mark_read_posts
    assert_css "#navbar-messages a[aria-label='1 unread message']"
    assert_not reply.reload.read?(@ranger.id)
  end

  # Review finding V10: two replies land close together, so the page posts mark
  # read twice, and the first answer was rendered before the second reply
  # existed. Applied after that reply's card landed, it must leave the card be.
  test "a mark-read answer from before a later reply leaves that reply's card" do
    open_thread
    page.execute_script(<<~JS)
      window.held = []
      const fetch = window.fetch
      window.fetch = async (resource, options) => {
        const response = await fetch(resource, options)
        if (String(resource).includes("/mark-read")) await new Promise((release) => window.held.push(release))
        return response
      }
    JS

    first = deliver(reply_to: @thread)
    # Answered, so the server rendered the thread before the second reply.
    assert_eventually("the first answer") { page.evaluate_script("window.held.length") == 1 }
    second = deliver(reply_to: @thread)
    second_card = "#messages-thread article##{ActionView::RecordIdentifier.dom_id(second, :card)}"
    assert_selector "#{second_card}[data-unread]"
    assert_eventually("the second answer") { page.evaluate_script("window.held.length") == 2 }

    page.execute_script("window.held.shift()()")
    assert_no_selector "#messages-thread article##{ActionView::RecordIdentifier.dom_id(first, :card)}[data-unread]"
    assert_selector "#{second_card}[data-unread]"

    page.execute_script("window.held.shift()()")
    assert_no_selector "#{second_card}[data-unread]"
    assert_selector "#messages-thread article", count: 3
  end

  # The form's answer appends the author's card, and so does the broadcast to
  # their own view of the thread: the card's id makes the second replace the
  # first.
  test "the author's own reply shows once" do
    open_thread
    page.execute_script(<<~JS)
      window.cardsAdded = 0
      new MutationObserver((records) => records.forEach((record) =>
        record.addedNodes.forEach((node) => { if (node.matches?.("article")) window.cardsAdded++ })
      )).observe(document.getElementById("messages-thread"), { childList: true })
    JS

    wait_for_rich_text_editor
    type_into_rich_text_editor("Bringing it now")
    click_on "Send Reply"

    assert_eventually("the form's card and the broadcast's") { page.evaluate_script("window.cardsAdded") >= 2 }
    assert_selector "#messages-thread article", count: 2
    assert_selector "#messages-thread article", text: "Bringing it now", count: 1
    assert_empty mark_read_posts, "the author's own card is read"
  end

  # The read a reply's arrival posts morphs the cards with no search
  # (MessagesConcern#card_streams): the page keeps the marks and the ring the
  # thread was opened with, and the card that just landed in the log gains none.
  test "a reply that lands in a thread opened from a search leaves the marks as they were" do
    open_thread(q: "has")
    top = "#messages-thread article##{ActionView::RecordIdentifier.dom_id(@thread, :card)}"
    assert_selector "#{top}[data-landing] mark.search-hit", text: "has"

    reply = PersonMessage.create!(person: @ranger, sender_person: @sender, creator_person: @sender, reply_to: @thread,
                                  sender_type: PersonMessage::SENDER_TYPE_PERSON, subject: @thread.subject,
                                  body: "<p>Nobody has it yet</p>")

    card = "#messages-thread article##{ActionView::RecordIdentifier.dom_id(reply, :card)}"
    assert_selector card, text: "Nobody has it yet"
    # Read: the mark-read answer has morphed the cards.
    assert_no_selector "#{card}[data-unread]"
    assert_selector "#{top}[data-landing] mark.search-hit", text: "has"
    assert_no_selector "#{card} mark"
    assert_no_selector "#{card}[data-landing]"
  end

  # A reply's broadcast redraws the thread's row knowing no list
  # (common/messages/_list_reply): in a search's list the row keeps its address,
  # search and all, and its Sent chip.
  test "a reply leaves a search's row its address and its Sent chip" do
    owner = person(:inactive_ranger)
    radio = person_message(:search_radio_archived)
    person_message_member(:search_radio_archived_inactive_ranger).update!(archived: false)
    sign_in(owner)
    visit me_messages_path(q: "radio")
    row = "a.review-line[data-review-id='#{radio.id}'][href='#{me_message_path(radio, folder: PersonMessage::FOLDER_INBOX, q: "radio")}']"
    assert_selector row, text: "Sent"
    list = Turbo::StreamsChannel.signed_stream_name([owner, :messages, "me"])
    assert_selector "turbo-cable-stream-source[connected][signed-stream-name='#{list}']", visible: :all

    PersonMessage.create!(person: person(:plate_collision_ranger), sender_person: owner, creator_person: owner,
                          reply_to: radio, sender_type: PersonMessage::SENDER_TYPE_PERSON, subject: radio.subject,
                          body: "Batteries are charged")

    assert_selector row, text: "Batteries are charged"
    assert_selector "#{row} .badge", text: "Sent"
  end

  private

  # A message from CustomGender to TestRanger, or a reply in their thread.
  def deliver(subject = "Radio handoff", reply_to: nil)
    PersonMessage.create!(person: @ranger, sender_person: @sender, creator_person: @sender, reply_to:,
                          sender_type: PersonMessage::SENDER_TYPE_PERSON, subject:,
                          body: reply_to ? "<p>On my <strong>way</strong></p>" : "Who has it?")
  end

  # Signed in, on a new thread with its three streams subscribed (the layout's,
  # the mailbox list's and the thread's) and thread-live connected, recording what the page posts and what
  # the envelope says.
  def open_thread(q: nil)
    @thread = deliver
    sign_in(@ranger)
    visit me_message_path(@thread, q:)
    assert_selector "turbo-cable-stream-source[connected]", count: 3, visible: :all
    wait_for_controller("thread-live", "#messages-thread")
    page.execute_script(<<~JS)
      window.posts = []
      window.postBodies = []
      const fetch = window.fetch
      window.fetch = (resource, options) => {
        const url = new URL(resource, location)
        if (options?.method?.toUpperCase() === "POST") {
          window.posts.push(url.pathname + url.search)
          window.postBodies.push([url.pathname, options.body instanceof FormData ? Object.fromEntries(options.body) : null])
        }
        return fetch(resource, options)
      }
      window.envelopes = []
      new MutationObserver(() => {
        const label = document.querySelector("#navbar-messages a")?.getAttribute("aria-label")
        if (label && label !== window.envelopes.at(-1)) window.envelopes.push(label)
      }).observe(document.getElementById("navbar-messages").parentElement, { childList: true, subtree: true })
    JS
  end

  def mark_read_posts = page.evaluate_script("window.posts").grep(%r{/mark-read})

  def mark_read_bodies = page.evaluate_script("window.postBodies").filter_map { |path, body| body if path.include?("/mark-read") }
end
