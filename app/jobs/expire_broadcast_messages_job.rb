# frozen_string_literal: true

class ExpireBroadcastMessagesJob < ApplicationJob
  def perform
    PersonMessage.expire_broadcasts!
  end
end
