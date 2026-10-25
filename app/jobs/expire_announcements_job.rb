# frozen_string_literal: true

class ExpireAnnouncementsJob < ApplicationJob
  def perform
    Motd.expire!
  end
end
