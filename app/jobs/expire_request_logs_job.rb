# frozen_string_literal: true

class ExpireRequestLogsJob < ApplicationJob
  def perform
    RequestLog.expire
  end
end
