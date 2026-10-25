# frozen_string_literal: true

require "test_helper"

class DashboardTasks::SignNdaTest < ActiveSupport::TestCase
  def facts(**overrides) = DashboardFacts.new(**overrides)

  test "skips when nda is not required" do
    result = DashboardTasks::SignNda.check(facts(nda_required: false))
    assert_equal DashboardTask::STATUS_SKIP, result.result
  end

  test "skips when nda_required is nil" do
    result = DashboardTasks::SignNda.check(facts(nda_required: nil))
    assert_equal DashboardTask::STATUS_SKIP, result.result
  end

  test "urgent when nda is required" do
    result = DashboardTasks::SignNda.check(facts(nda_required: true))
    assert_equal DashboardTask::STATUS_URGENT, result.result
    assert_equal "sign_nda_needed", result.partial
  end

  test "is an immediate task" do
    assert DashboardTasks::SignNda.immediate
  end
end
