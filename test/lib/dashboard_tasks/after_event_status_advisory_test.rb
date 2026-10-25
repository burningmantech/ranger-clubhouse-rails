# frozen_string_literal: true

require "test_helper"

class DashboardTasks::AfterEventStatusAdvisoryTest < ActiveSupport::TestCase
  def facts(**overrides) = DashboardFacts.new(**overrides)

  test "skips when status is not retired, inactive, or inactive extension" do
    result = DashboardTasks::AfterEventStatusAdvisory.check(facts(status: Person::ACTIVE))
    assert_equal DashboardTask::STATUS_SKIP, result.result
  end

  test "inactive status returns a note advisory" do
    result = DashboardTasks::AfterEventStatusAdvisory.check(facts(status: Person::INACTIVE))
    assert_equal DashboardTask::STATUS_NOTE, result.result
    assert_equal "after_event_status_advisory", result.partial
  end

  test "retired status returns a note advisory" do
    result = DashboardTasks::AfterEventStatusAdvisory.check(facts(status: Person::RETIRED))
    assert_equal DashboardTask::STATUS_NOTE, result.result
    assert_equal "after_event_status_advisory", result.partial
  end

  test "inactive extension status returns a note advisory" do
    result = DashboardTasks::AfterEventStatusAdvisory.check(facts(status: Person::INACTIVE_EXTENSION))
    assert_equal DashboardTask::STATUS_NOTE, result.result
    assert_equal "after_event_status_advisory", result.partial
  end
end
