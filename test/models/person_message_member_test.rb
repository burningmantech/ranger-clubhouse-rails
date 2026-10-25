# frozen_string_literal: true

require "test_helper"

# The member model (.scratch/messaging-rework/member-model-plan.md): every way
# a message is made or marked writes its thread's member rows, which hold each
# person's read and archive state. Sending through the mailbox, Archive and an
# RBS copy are checked where they are tested (Me::MessagesControllerTest,
# RbsTest).
class PersonMessageMemberTest < ActiveSupport::TestCase
  include GroupMessageTestHelper

  setup do
    @author = person(:active_ranger)
    @other = person(:ranger_with_custom_gender)
  end

  test "a one-to-one message: its recipient has never read it, its sender has" do
    top = letter(@author, to: @other)

    assert_equal({ @other.id => nil, @author.id => top.id }, watermarks(top))
  end

  test "a note to self is one member, who has read it" do
    top = letter(@author, to: @author)

    assert_equal({ @author.id => top.id }, watermarks(top))
  end

  test "a walk-up, from no sender person, has its recipient alone" do
    top = PersonMessage.create!(person: @other, creator_person: @author, sender_type: PersonMessage::SENDER_TYPE_OTHER,
                                message_from: "Outpost 3", subject: "Lost radio", body: "Left at the window.")

    assert_equal({ @other.id => nil }, watermarks(top))
  end

  test "a reply adds no member, and is unread for the other party" do
    top = letter(@author, to: @other)
    top.mark_thread_read!(@other.id)

    assert_no_difference -> { PersonMessageMember.count } do
      letter(@other, to: @author, reply_to: top)
    end
    assert_includes PersonMessage.unread_for_person(@author.id), top
    assert_not_includes PersonMessage.unread_for_person(@other.id), top
  end

  test "Mark Read reads the member through the rows shown, and Mark Unread puts it before the other party's newest" do
    top = letter(@author, to: @other)
    reply = letter(@other, to: @author, reply_to: top)

    assert_equal true, top.reload.toggle_thread_read!(@author.id)
    assert_equal reply.id, watermarks(top)[@author.id]

    assert_equal false, top.reload.toggle_thread_read!(@author.id)
    assert_equal reply.id - 1, watermarks(top)[@author.id]
  end

  test "Mark Unread on a thread nobody has answered makes it never read" do
    top = letter(@author, to: @other)

    assert_equal false, top.toggle_thread_read!(@author.id)
    assert_nil watermarks(top)[@author.id]
    assert_includes PersonMessage.unread_for_person(@author.id), top
  end

  test "a group top's author has read it through its id" do
    top = create_group_thread(@author, @other)

    assert_equal({ @author.id => top.id, @other.id => nil }, watermarks(top))
  end

  private

  def letter(sender, to:, reply_to: nil)
    PersonMessage.create!(person: to, sender_person: sender, creator_person: sender, reply_to:, subject: "Radios",
                          body: "Who has them?", sender_type: PersonMessage::SENDER_TYPE_PERSON)
  end

  # Each member's last_read_message_id, by person id, as saved.
  def watermarks(top) = PersonMessageMember.where(person_message: top).pluck(:person_id, :last_read_message_id).to_h
end
