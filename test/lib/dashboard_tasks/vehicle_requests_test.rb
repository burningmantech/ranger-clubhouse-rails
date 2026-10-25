# frozen_string_literal: true

require "test_helper"
require "ostruct"

class DashboardTasks::VehicleRequestsTest < ActiveSupport::TestCase
  def facts(**overrides) = DashboardFacts.new(**overrides)

  def request(status) = OpenStruct.new(status: status)

  test "skip_period metadata" do
    assert_equal [DashboardTask::POST_EVENT, DashboardTask::AFTER_EVENT],
                 DashboardTasks::VehicleRequests.skip_period
  end

  test "skips when motorpool agreement unavailable" do
    result = DashboardTasks::VehicleRequests.check(
      facts(motorpool_agreement_available: false, pvr_eligible: true, pvr_potential: true)
    )
    assert_equal DashboardTask::STATUS_SKIP, result.result
  end

  test "skips when neither pvr_eligible nor pvr_potential" do
    result = DashboardTasks::VehicleRequests.check(
      facts(motorpool_agreement_available: true, pvr_eligible: false, pvr_potential: false)
    )
    assert_equal DashboardTask::STATUS_SKIP, result.result
  end

  test "completed when a vehicle request is approved" do
    result = DashboardTasks::VehicleRequests.check(
      facts(motorpool_agreement_available: true, pvr_eligible: true, pvr_potential: false,
            vehicle_requests: [request(Vehicle::APPROVED)])
    )
    assert_equal DashboardTask::STATUS_COMPLETED, result.result
    assert_equal "vehicle_requests_approved", result.partial
  end

  test "waiting when a vehicle request is pending" do
    result = DashboardTasks::VehicleRequests.check(
      facts(motorpool_agreement_available: true, pvr_eligible: true, pvr_potential: false,
            vehicle_requests: [request(Vehicle::PENDING)])
    )
    assert_equal DashboardTask::STATUS_WAITING, result.result
    assert_equal "vehicle_requests_pending", result.partial
  end

  test "urgent when a vehicle request is rejected" do
    result = DashboardTasks::VehicleRequests.check(
      facts(motorpool_agreement_available: true, pvr_eligible: true, pvr_potential: false,
            vehicle_requests: [request(Vehicle::REJECTED)])
    )
    assert_equal DashboardTask::STATUS_URGENT, result.result
    assert_equal "vehicle_requests_denied", result.partial
  end

  test "completed and muted when ignore_pvr is set" do
    result = DashboardTasks::VehicleRequests.check(
      facts(motorpool_agreement_available: true, pvr_eligible: true, pvr_potential: false,
            vehicle_requests: nil, ignore_pvr: true)
    )
    assert_equal DashboardTask::STATUS_COMPLETED, result.result
    assert_equal "vehicle_requests_muted", result.partial
    assert_equal "Personal Vehicle Request Eligible (Muted)", result.title
  end

  test "muted branch reached when requests present but none match a known status" do
    result = DashboardTasks::VehicleRequests.check(
      facts(motorpool_agreement_available: true, pvr_eligible: true, pvr_potential: false,
            vehicle_requests: [request("unknown")], ignore_pvr: true)
    )
    assert_equal DashboardTask::STATUS_COMPLETED, result.result
    assert_equal "vehicle_requests_muted", result.partial
  end

  test "action needed when eligible with no requests and not muted" do
    result = DashboardTasks::VehicleRequests.check(
      facts(motorpool_agreement_available: true, pvr_eligible: false, pvr_potential: true,
            vehicle_requests: nil, ignore_pvr: false)
    )
    assert_equal DashboardTask::STATUS_ACTION_NEEDED, result.result
    assert_equal "vehicle_requests_eligible", result.partial
  end

  test "action needed when requests present but none match and not muted" do
    result = DashboardTasks::VehicleRequests.check(
      facts(motorpool_agreement_available: true, pvr_eligible: true, pvr_potential: false,
            vehicle_requests: [request("unknown")], ignore_pvr: false)
    )
    assert_equal DashboardTask::STATUS_ACTION_NEEDED, result.result
    assert_equal "vehicle_requests_eligible", result.partial
  end
end
