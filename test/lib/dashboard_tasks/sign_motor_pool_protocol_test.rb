# frozen_string_literal: true

require "test_helper"
require "ostruct"

class DashboardTasks::SignMotorPoolProtocolTest < ActiveSupport::TestCase
  def facts(**overrides) = DashboardFacts.new(**overrides)

  test "skips when motorpool agreement not available" do
    result = DashboardTasks::SignMotorPoolProtocol.check(facts(motorpool_agreement_available: false))
    assert_equal DashboardTask::STATUS_SKIP, result.result
  end

  test "completed when motorpool agreement already signed" do
    result = DashboardTasks::SignMotorPoolProtocol.check(
      facts(motorpool_agreement_available: true, motorpool_agreement_signed: true)
    )
    assert_equal DashboardTask::STATUS_COMPLETED, result.result
  end

  test "blocked for applicant without passed training" do
    result = DashboardTasks::SignMotorPoolProtocol.check(
      facts(
        motorpool_agreement_available: true,
        motorpool_agreement_signed: false,
        is_applicant: true,
        training: OpenStruct.new(status: Training::FAIL)
      )
    )
    assert_equal DashboardTask::STATUS_NOT_AVAILABLE, result.result
    assert_equal "sign_motor_pool_protocol_blocked", result.partial
  end

  test "blocked for applicant with no training (nil training)" do
    result = DashboardTasks::SignMotorPoolProtocol.check(
      facts(
        motorpool_agreement_available: true,
        motorpool_agreement_signed: false,
        is_applicant: true,
        training: nil
      )
    )
    assert_equal DashboardTask::STATUS_NOT_AVAILABLE, result.result
    assert_equal "sign_motor_pool_protocol_blocked", result.partial
  end

  test "action needed for applicant with passed training and mvr eligible" do
    result = DashboardTasks::SignMotorPoolProtocol.check(
      facts(
        motorpool_agreement_available: true,
        motorpool_agreement_signed: false,
        is_applicant: true,
        training: OpenStruct.new(status: Training::PASS),
        mvr_eligible: true
      )
    )
    assert_equal DashboardTask::STATUS_ACTION_NEEDED, result.result
    assert_equal "sign_motor_pool_protocol_needed", result.partial
  end

  test "action needed for non-applicant when mvr eligible" do
    result = DashboardTasks::SignMotorPoolProtocol.check(
      facts(
        motorpool_agreement_available: true,
        motorpool_agreement_signed: false,
        is_applicant: false,
        mvr_eligible: true
      )
    )
    assert_equal DashboardTask::STATUS_ACTION_NEEDED, result.result
    assert_equal "sign_motor_pool_protocol_needed", result.partial
  end

  test "optional for non-applicant when not mvr eligible" do
    result = DashboardTasks::SignMotorPoolProtocol.check(
      facts(
        motorpool_agreement_available: true,
        motorpool_agreement_signed: false,
        is_applicant: false,
        mvr_eligible: false
      )
    )
    assert_equal DashboardTask::STATUS_OPTIONAL, result.result
    assert_equal "sign_motor_pool_protocol_needed", result.partial
  end

  test "optional for applicant with passed training when not mvr eligible" do
    result = DashboardTasks::SignMotorPoolProtocol.check(
      facts(
        motorpool_agreement_available: true,
        motorpool_agreement_signed: false,
        is_applicant: true,
        training: OpenStruct.new(status: Training::PASS),
        mvr_eligible: false
      )
    )
    assert_equal DashboardTask::STATUS_OPTIONAL, result.result
    assert_equal "sign_motor_pool_protocol_needed", result.partial
  end

  test "title metadata" do
    assert_equal "Sign the Ranger Vehicle Use Protocol", DashboardTasks::SignMotorPoolProtocol.title
  end

  test "skip_period metadata" do
    assert_equal [DashboardTask::POST_EVENT, DashboardTask::AFTER_EVENT],
                 DashboardTasks::SignMotorPoolProtocol.skip_period
  end
end
