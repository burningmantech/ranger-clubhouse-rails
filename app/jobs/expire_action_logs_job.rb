# frozen_string_literal: true

class ExpireActionLogsJob < ApplicationJob
  def perform
    ActionLog.expire
  end
end
