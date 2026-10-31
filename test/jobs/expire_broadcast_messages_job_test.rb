# frozen_string_literal: true

require "test_helper"

class ExpireBroadcastMessagesJobTest < ActiveSupport::TestCase
  def create_message(sender_type, expires_at)
    recipient = person(:active_ranger)
    PersonMessage.create!(person: recipient, creator_person: recipient, message_from: "Ranger HQ", sender_type:,
                          subject: "Hold at your post", body: "Dust storm.", expires_at:)
  end

  test "perform deletes expired broadcasts and leaves the rest" do
    expired = create_message(PersonMessage::SENDER_TYPE_RBS, Current.time - 1.minute)
    active = create_message(PersonMessage::SENDER_TYPE_RBS, Current.time + 1.hour)
    lasting = create_message(PersonMessage::SENDER_TYPE_RBS, nil)
    other = create_message(PersonMessage::SENDER_TYPE_OTHER, Current.time - 1.minute)

    ExpireBroadcastMessagesJob.perform_now

    assert_not PersonMessage.exists?(expired.id)
    assert_empty PersonMessageMember.where(person_message_id: expired.id)
    assert_equal [active.id, lasting.id, other.id].sort, PersonMessage.where(id: [active, lasting, other]).ids.sort
  end
end
