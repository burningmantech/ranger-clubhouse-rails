# frozen_string_literal: true

require "test_helper"

class ExpireAnonymousPageVisitsJobTest < ActiveSupport::TestCase
  test "perform removes page visits with no person past 48 hours and nothing else" do
    freeze_time do
      cutoff = ActionLog::EXPIRE_PAGE_VISIT_HOURS.hours.ago
      old = record("page-visit", nil, cutoff)
      recent = record("page-visit", nil, cutoff + 1.second)
      signed_in = record("page-visit", person(:active_ranger).id, cutoff - 1.day)
      system_change = record("person-update", nil, cutoff - 1.day)

      ExpireAnonymousPageVisitsJob.perform_now

      assert_not ActionLog.exists?(old.id)
      assert ActionLog.exists?(recent.id)
      assert ActionLog.exists?(signed_in.id), "a signed-in visit is kept"
      assert ActionLog.exists?(system_change.id), "a change made by the system is kept"
    end
  end

  test "expire works through every batch and reports how many rows went" do
    3.times { record("page-visit", nil, 3.days.ago) }

    assert_equal 3, ActionLog.expire_anonymous_page_visits(batch_size: 2, pause: 0)
    assert_not ActionLog.where(event: "page-visit", person_id: nil).exists?
  end

  private

  def record(event, person_id, created_at)
    ActionLog.create!(event:, message: "/", person_id:, created_at:)
  end
end
