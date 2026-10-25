# frozen_string_literal: true

require "test_helper"

class DashboardTasks::BmidWillNotBePrintedTest < ActiveSupport::TestCase
  def facts(**overrides) = DashboardFacts.new(**overrides)

  test "skips when the month is neither July nor August" do
    result = DashboardTasks::BmidWillNotBePrinted.check(facts(now: Time.utc(2026, 6, 14)))
    assert_equal DashboardTask::STATUS_SKIP, result.result
  end

  test "skips in July when the person is bmid_qualified" do
    result = DashboardTasks::BmidWillNotBePrinted.check(facts(now: Time.utc(2026, 7, 15), bmid_qualified: true))
    assert_equal DashboardTask::STATUS_SKIP, result.result
  end

  test "skips in August when the person is bmid_qualified" do
    result = DashboardTasks::BmidWillNotBePrinted.check(facts(now: Time.utc(2026, 8, 15), bmid_qualified: true))
    assert_equal DashboardTask::STATUS_SKIP, result.result
  end

  test "urgent in July when the person is not bmid_qualified" do
    result = DashboardTasks::BmidWillNotBePrinted.check(facts(now: Time.utc(2026, 7, 15), bmid_qualified: false))
    assert_equal DashboardTask::STATUS_URGENT, result.result
    assert_equal "bmid_will_not_be_printed", result.partial
  end

  test "urgent in August when the person is not bmid_qualified" do
    result = DashboardTasks::BmidWillNotBePrinted.check(facts(now: Time.utc(2026, 8, 15), bmid_qualified: false))
    assert_equal DashboardTask::STATUS_URGENT, result.result
    assert_equal "bmid_will_not_be_printed", result.partial
  end

  test "skip_period skips post-event and after-event periods" do
    assert_equal [DashboardTask::POST_EVENT, DashboardTask::AFTER_EVENT],
                 DashboardTasks::BmidWillNotBePrinted.skip_period
  end

  test "task is immediate" do
    assert DashboardTasks::BmidWillNotBePrinted.immediate
  end
end
