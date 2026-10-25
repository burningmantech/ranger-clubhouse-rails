# frozen_string_literal: true

require "test_helper"

class DashboardTasks::SandmanAffidavitTest < ActiveSupport::TestCase
  def facts(**overrides) = DashboardFacts.new(**overrides)

  test "completed when sandman affidavit already signed" do
    result = DashboardTasks::SandmanAffidavit.check(facts(sandman_affidavit_signed: true))
    assert_equal DashboardTask::STATUS_COMPLETED, result.result
  end

  test "urgent and immediate when affidavit required and not signed" do
    result = DashboardTasks::SandmanAffidavit.check(
      facts(sandman_affidavit_signed: false, sandman_affidavit_required: true)
    )
    assert_equal DashboardTask::STATUS_URGENT, result.result
    assert_equal "sandman_affidavit_needed", result.partial
    assert result.immediate
  end

  test "skip when not signed and not required" do
    result = DashboardTasks::SandmanAffidavit.check(
      facts(sandman_affidavit_signed: false, sandman_affidavit_required: false)
    )
    assert_equal DashboardTask::STATUS_SKIP, result.result
  end

  test "skip_period excludes post-event and after-event" do
    assert_equal [DashboardTask::POST_EVENT, DashboardTask::AFTER_EVENT],
                 DashboardTasks::SandmanAffidavit.skip_period
  end
end
