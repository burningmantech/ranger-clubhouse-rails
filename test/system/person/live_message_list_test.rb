# frozen_string_literal: true

require "application_system_test_case"

# A reply that lands in a thread moves its row and the Unread count in every
# list showing that mailbox (PersonMessage#announce_to_recipient), here a
# manager's Person › Messages, which reads the person's mail without marking
# it read. It swaps in the in-process async cable adapter, as
# test/system/me/live_message_arrival_test.rb explains.
class Person::LiveMessageListTest < ApplicationSystemTestCase
  include TimesheetAdminTestHelper # ensure_role / grant_role

  setup do
    @manager = person(:echelon_ranger)
    @ranger = person(:active_ranger)
    @sender = person(:ranger_with_custom_gender)
    ensure_role(Role::EVENT_MANAGEMENT, "Event Management")
    grant_role(@manager, Role::EVENT_MANAGEMENT)
    @cable = ActionCable.server
    @recorded = @cable.pubsub
    @cable.instance_variable_set(:@pubsub, ActionCable::SubscriptionAdapter::Async.new(@cable))
  end

  teardown do
    @cable.pubsub.shutdown
    @cable.instance_variable_set(:@pubsub, @recorded)
    Current.reset
  end

  test "a reply gives the open thread's row its New Reply chip and raises the Unread count" do
    thread = deliver
    thread.mark_thread_read!(@ranger.id)
    sign_in(@manager)
    visit person_message_path(@ranger, thread)
    row = "a.review-line[data-review-id='#{thread.id}']"
    assert_selector "#{row}[aria-current=true]", text: "Radio handoff"
    assert_no_selector "#{row} .badge"
    assert_selector "#messages-unread-count[hidden]", visible: :hidden
    list = Turbo::StreamsChannel.signed_stream_name([@ranger, :messages, "person"])
    assert_selector "turbo-cable-stream-source[connected][signed-stream-name='#{list}']", visible: :all

    reply = deliver(reply_to: thread)

    assert_selector "#{row}.messages-conversation-unread .badge", text: "New Reply"
    assert_selector "#{row}[aria-current=true][href='#{person_message_path(@ranger, thread)}']"
    assert_selector "#messages-folder-selector a[role=tab][aria-selected=true]", text: "Inbox"
    assert_selector "#messages-unread-count", text: "1"
    assert_selector "#messages-thread article", text: "On my way"
    assert_not reply.reload.read?(@ranger.id), "a manager's page never marks the person's mail read"
  end

  # Review finding 14: the row was replaced, and the reader's keyboard focus
  # went with the old link.
  test "a reply morphs the row in place, so its link keeps the focus and the open row's mark" do
    thread = deliver
    sign_in(@manager)
    visit person_message_path(@ranger, thread)
    row = "a.review-line[data-review-id='#{thread.id}']"
    assert_selector "#{row}[aria-current=true]"
    list = Turbo::StreamsChannel.signed_stream_name([@ranger, :messages, "person"])
    assert_selector "turbo-cable-stream-source[connected][signed-stream-name='#{list}']", visible: :all
    page.execute_script("document.querySelector(#{row.to_json}).focus()")

    deliver(reply_to: thread)

    assert_selector "#{row} .badge", text: "New Reply"
    assert_selector "#{row}[aria-current=true]"
    assert_equal thread.id.to_s, page.evaluate_script("document.activeElement?.dataset?.reviewId")
  end

  private

  # A message from CustomGender to TestRanger, or a reply in their thread.
  def deliver(reply_to: nil)
    PersonMessage.create!(person: @ranger, sender_person: @sender, creator_person: @sender, reply_to:,
                          sender_type: PersonMessage::SENDER_TYPE_PERSON, subject: "Radio handoff",
                          body: reply_to ? "On my way" : "Who has it?", created_at: reply_to ? Time.current : 1.minute.ago)
  end
end
