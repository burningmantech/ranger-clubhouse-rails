# frozen_string_literal: true

# Broadcast (RBS) messages are the only ones that expire, and an expired one
# reads as gone already (PersonMessage#has_expired?). One at a time: a
# broadcast makes a row per recipient, and destroy takes its member rows and
# any replies with it.
class ExpireBroadcastMessagesJob < ApplicationJob
  def perform
    PersonMessage.where(sender_type: PersonMessage::SENDER_TYPE_RBS, expires_at: ..Current.time).find_each(&:destroy!)
  end
end
