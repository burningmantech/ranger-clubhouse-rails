# frozen_string_literal: true

require "test_helper"
require "ostruct"

class DashboardTasks::SignRadioCheckoutAgreementTest < ActiveSupport::TestCase
  def facts(**overrides) = DashboardFacts.new(**overrides)

  test "asset already authorized is completed" do
    result = DashboardTasks::SignRadioCheckoutAgreement.check(facts(asset_authorized: true))
    assert_equal DashboardTask::STATUS_COMPLETED, result.result
  end

  test "applicant without passed training is blocked" do
    result = DashboardTasks::SignRadioCheckoutAgreement.check(
      facts(asset_authorized: false, is_applicant: true, training: OpenStruct.new(status: "fail"))
    )
    assert_equal DashboardTask::STATUS_NOT_AVAILABLE, result.result
    assert_equal "sign_radio_checkout_agreement_blocked", result.partial
  end

  test "applicant with nil training is blocked" do
    result = DashboardTasks::SignRadioCheckoutAgreement.check(
      facts(asset_authorized: false, is_applicant: true, training: nil)
    )
    assert_equal DashboardTask::STATUS_NOT_AVAILABLE, result.result
    assert_equal "sign_radio_checkout_agreement_blocked", result.partial
  end

  test "applicant with passed training but agreement not enabled is not available" do
    result = DashboardTasks::SignRadioCheckoutAgreement.check(
      facts(
        asset_authorized: false,
        is_applicant: true,
        training: OpenStruct.new(status: Training::PASS),
        radio_checkout_agreement_enabled: false
      )
    )
    assert_equal DashboardTask::STATUS_NOT_AVAILABLE, result.result
    assert_equal "sign_radio_checkout_agreement_not_available", result.partial
  end

  test "non-applicant with agreement not enabled is skipped" do
    result = DashboardTasks::SignRadioCheckoutAgreement.check(
      facts(asset_authorized: false, is_applicant: false, radio_checkout_agreement_enabled: false)
    )
    assert_equal DashboardTask::STATUS_SKIP, result.result
  end

  test "agreement enabled in August is urgent and immediate" do
    result = DashboardTasks::SignRadioCheckoutAgreement.check(
      facts(
        asset_authorized: false,
        is_applicant: false,
        radio_checkout_agreement_enabled: true,
        now: Time.utc(2026, 8, 15)
      )
    )
    assert_equal DashboardTask::STATUS_URGENT, result.result
    assert result.immediate
    assert_equal "sign_radio_checkout_agreement_needed", result.partial
  end

  test "agreement enabled outside August is action needed and not immediate" do
    result = DashboardTasks::SignRadioCheckoutAgreement.check(
      facts(
        asset_authorized: false,
        is_applicant: false,
        radio_checkout_agreement_enabled: true,
        now: Time.utc(2026, 7, 15)
      )
    )
    assert_equal DashboardTask::STATUS_ACTION_NEEDED, result.result
    assert_not result.immediate
    assert_equal "sign_radio_checkout_agreement_needed", result.partial
  end

  test "applicant with passed training and agreement enabled reaches needed branch" do
    result = DashboardTasks::SignRadioCheckoutAgreement.check(
      facts(
        asset_authorized: false,
        is_applicant: true,
        training: OpenStruct.new(status: Training::PASS),
        radio_checkout_agreement_enabled: true,
        now: Time.utc(2026, 7, 15)
      )
    )
    assert_equal DashboardTask::STATUS_ACTION_NEEDED, result.result
    assert_equal "sign_radio_checkout_agreement_needed", result.partial
  end

  test "skip_period metadata" do
    assert_equal [DashboardTask::POST_EVENT, DashboardTask::AFTER_EVENT],
                 DashboardTasks::SignRadioCheckoutAgreement.skip_period
  end

  test "title metadata" do
    assert_equal "Sign the Ranger Equipment Checkout Agreement",
                 DashboardTasks::SignRadioCheckoutAgreement.title
  end
end
