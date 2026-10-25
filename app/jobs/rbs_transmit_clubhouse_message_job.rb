# frozen_string_literal: true

# Puts a broadcast in each recipient's Clubhouse inbox, away from the page the
# sender is looking at.
class RbsTransmitClubhouseMessageJob < ApplicationJob
  FROM = "The Ranger Broadcasting System"

  def perform(broadcast_id, sender_id, person_ids, subject, message, expires_at)
    Rbs.broadcast_message(broadcast_id, sender_id, person_ids, FROM, subject, message, expires_at)
  end
end
