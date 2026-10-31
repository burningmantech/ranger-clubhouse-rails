# frozen_string_literal: true

class ExpireAnonymousPageVisitsJob < ApplicationJob
  def perform
    ActionLog.expire_anonymous_page_visits
  end
end
