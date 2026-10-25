# frozen_string_literal: true

require "test_helper"

class DashboardTasks::SignBehavioralAgreementTest < ActiveSupport::TestCase
  def facts(**overrides) = DashboardFacts.new(**overrides)

  test "signed agreement and applicant marks task completed" do
    result = DashboardTasks::SignBehavioralAgreement.check(
      facts(behavioral_agreement: true, is_applicant: true)
    )
    assert_equal DashboardTask::STATUS_COMPLETED, result.result
  end

  test "signed agreement and non-applicant skips task" do
    result = DashboardTasks::SignBehavioralAgreement.check(
      facts(behavioral_agreement: true, is_applicant: false)
    )
    assert_equal DashboardTask::STATUS_SKIP, result.result
  end

  test "unsigned agreement returns optional with prompt partial" do
    result = DashboardTasks::SignBehavioralAgreement.check(
      facts(behavioral_agreement: false)
    )
    assert_equal DashboardTask::STATUS_OPTIONAL, result.result
    assert_equal "sign_behavioral_agreement_optional", result.partial
  end

  test "skip_period excludes post-event and after-event periods" do
    assert_equal [DashboardTask::POST_EVENT, DashboardTask::AFTER_EVENT],
                 DashboardTasks::SignBehavioralAgreement.skip_period
  end
end
