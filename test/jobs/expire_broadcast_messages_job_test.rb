# frozen_string_literal: true

require "test_helper"

class ExpireBroadcastMessagesJobTest < ActiveSupport::TestCase
  def create_message(sender_type, expires_at, **attributes)
    recipient = person(:active_ranger)
    PersonMessage.create!(person: recipient, creator_person: recipient, message_from: "Ranger HQ", sender_type:,
                          subject: "Hold at your post", body: "Dust storm.", expires_at:, **attributes)
  end

  test "perform deletes expired broadcasts and leaves the rest" do
    freeze_time do
      expired = create_message(PersonMessage::SENDER_TYPE_RBS, Current.time - 1.minute)
      expiring = create_message(PersonMessage::SENDER_TYPE_RBS, Current.time)
      active = create_message(PersonMessage::SENDER_TYPE_RBS, Current.time + 1.second)
      lasting = create_message(PersonMessage::SENDER_TYPE_RBS, nil)
      other = create_message(PersonMessage::SENDER_TYPE_OTHER, Current.time - 1.minute)
      # A Clubhouse 2 reply: broadcasts take none now (#accepts_replies?).
      recipient = person(:active_ranger)
      reply = PersonMessage.new(person: recipient, creator_person: recipient, message_from: "Ranger HQ",
                                sender_type: PersonMessage::SENDER_TYPE_OTHER, subject: "Re", body: "Copy.",
                                reply_to: expired)
      reply.save!(validate: false)

      ExpireBroadcastMessagesJob.perform_now

      assert_empty PersonMessage.where(id: [expired, expiring, reply])
      assert_empty PersonMessageMember.where(person_message_id: [expired, expiring])
      kept = [active, lasting, other]
      assert_equal kept.map(&:id).sort, PersonMessage.where(id: kept).ids.sort
      assert_equal kept.map(&:id).sort, PersonMessageMember.where(person_message_id: kept).pluck(:person_message_id).sort
    end
  end
end
