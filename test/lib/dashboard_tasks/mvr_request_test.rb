# frozen_string_literal: true

require "test_helper"

class DashboardTasks::MvrRequestTest < ActiveSupport::TestCase
  def facts(**overrides) = DashboardFacts.new(**overrides)

  test "skips when motorpool agreement unavailable" do
    result = DashboardTasks::MvrRequest.check(
      facts(motorpool_agreement_available: false, mvr_eligible: true, mvr_potential: true)
    )
    assert_equal DashboardTask::STATUS_SKIP, result.result
  end

  test "skips when neither mvr_eligible nor mvr_potential" do
    result = DashboardTasks::MvrRequest.check(
      facts(motorpool_agreement_available: true, mvr_eligible: false, mvr_potential: false)
    )
    assert_equal DashboardTask::STATUS_SKIP, result.result
  end

  test "completed and approved when org vehicle insurance present" do
    result = DashboardTasks::MvrRequest.check(
      facts(
        motorpool_agreement_available: true,
        mvr_eligible: true,
        mvr_potential: false,
        org_vehicle_insurance: true
      )
    )
    assert_equal DashboardTask::STATUS_COMPLETED, result.result
    assert_equal "mvr_request_approved", result.partial
  end

  test "completed and muted when mvr ignored" do
    result = DashboardTasks::MvrRequest.check(
      facts(
        motorpool_agreement_available: true,
        mvr_eligible: false,
        mvr_potential: true,
        org_vehicle_insurance: false,
        ignore_mvr: true
      )
    )
    assert_equal DashboardTask::STATUS_COMPLETED, result.result
    assert_equal "mvr_request_muted", result.partial
  end

  test "action needed and eligible when not insured and not ignored" do
    result = DashboardTasks::MvrRequest.check(
      facts(
        motorpool_agreement_available: true,
        mvr_eligible: true,
        mvr_potential: false,
        org_vehicle_insurance: false,
        ignore_mvr: false
      )
    )
    assert_equal DashboardTask::STATUS_ACTION_NEEDED, result.result
    assert_equal "mvr_request_eligible", result.partial
  end

  test "period metadata" do
    assert_equal [DashboardTask::BEFORE_EVENT, DashboardTask::DURING_EVENT], DashboardTasks::MvrRequest.period
  end
end
