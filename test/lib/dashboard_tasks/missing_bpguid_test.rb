# frozen_string_literal: true

require "test_helper"

class DashboardTasks::MissingBpguidTest < ActiveSupport::TestCase
  def facts(**overrides) = DashboardFacts.new(**overrides)

  test "missing_bpguid true returns urgent with missing_bpguid partial" do
    result = DashboardTasks::MissingBpguid.check(facts(missing_bpguid: true))
    assert_equal DashboardTask::STATUS_URGENT, result.result
    assert_equal "missing_bpguid", result.partial
  end

  test "missing_bpguid false skips the task" do
    result = DashboardTasks::MissingBpguid.check(facts(missing_bpguid: false))
    assert_equal DashboardTask::STATUS_SKIP, result.result
  end

  test "immediate is true" do
    assert DashboardTasks::MissingBpguid.immediate
  end
end
