# frozen_string_literal: true

class ExpireAnonymousSessionsJob < ApplicationJob
  def perform
    Session.expire_anonymous
  end
end
