# frozen_string_literal: true

require "test_helper"

class ExpireActionLogsJobTest < ActiveSupport::TestCase
  test "perform removes rows past the window, keeps the recent ones and every schedule event" do
    old = record("auth-login", (ActionLog::EXPIRE_YEARS_DEFAULT.years + 1.day).ago)
    recent = record("auth-login", 1.day.ago)
    old_signup = record("person-slot-add", (ActionLog::EXPIRE_YEARS_DEFAULT.years + 1.day).ago)

    ExpireActionLogsJob.perform_now

    assert_not ActionLog.exists?(old.id)
    assert ActionLog.exists?(recent.id)
    assert ActionLog.exists?(old_signup.id), "a sign-up's history is kept past the window"
  end

  test "expire reports how many rows went" do
    record("auth-login", 8.years.ago)
    record("auth-login", 9.years.ago)

    assert_equal 2, ActionLog.expire
  end

  private

  def record(event, created_at)
    ActionLog.create!(event:, message: "test", person_id: person(:active_ranger).id, created_at:)
  end
end
