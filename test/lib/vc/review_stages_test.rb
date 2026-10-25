# frozen_string_literal: true

require "test_helper"

class Vc::ReviewStagesTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  setup do
    travel_to Time.zone.local(2026, 4, 16, 12, 0, 0)
    Current.reset
  end

  teardown do
    Current.reset
    travel_back
  end

  def stages_for(fixture, **overrides)
    # Reload: the fixture accessor caches the record per test, and some tests
    # build several variants from the same fixture.
    application = prospective_application(fixture).reload
    application.assign_attributes(overrides) if overrides.any?
    Vc::ReviewStages.new(application)
  end

  def states(review_stages)
    review_stages.stages.to_h { |stage| [stage.key, stage.state] }
  end

  test "fresh qualified application: paragraph review is the first actionable stage" do
    review = stages_for(:pending_qualified)

    assert_equal({ eligibility: :done, paragraph: :todo, personal_info: :done,
                   callsign: :todo, decision: :todo }, states(review))
    assert_equal :paragraph, review.first_actionable.key
    assert_not review.post_decision?
  end

  test "unqualified under-18 application opens eligibility with its problems" do
    review = stages_for(:pending_unqualified)

    assert_equal :problem, review.stages.first.state
    assert_equal :eligibility, review.first_actionable.key
    assert_equal :problem, states(review)[:personal_info]
  end

  test "event-confirmation hold parks eligibility and moves on to the paragraph" do
    review = stages_for(:pending_unqualified,
                        status: ProspectiveApplication::STATUS_HOLD_QUALIFICATION_ISSUE, is_over_18: true)

    assert_equal :waiting, states(review)[:eligibility]
    assert_equal :paragraph, review.first_actionable.key
  end

  test "age-confirmation hold parks eligibility" do
    review = stages_for(:pending_unqualified, status: ProspectiveApplication::STATUS_HOLD_AGE_ISSUE)

    assert_equal :waiting, states(review)[:eligibility]
  end

  test "why-ranger problem without a hold is actionable, with a hold it waits" do
    problem = stages_for(:pending_qualified,
                         why_volunteer_review: ProspectiveApplication::WHY_VOLUNTEER_REVIEW_PROBLEM)
    assert_equal :problem, states(problem)[:paragraph]
    assert_equal :paragraph, problem.first_actionable.key

    held = stages_for(:pending_qualified,
                      why_volunteer_review: ProspectiveApplication::WHY_VOLUNTEER_REVIEW_PROBLEM,
                      status: ProspectiveApplication::STATUS_HOLD_WHY_RANGER_QUESTION)
    assert_equal :waiting, states(held)[:paragraph]
    assert_equal :callsign, held.first_actionable.key
  end

  test "handle-check application: callsign vetting is the open stage" do
    review = stages_for(:handle_check)

    assert_equal({ eligibility: :done, paragraph: :done, personal_info: :done,
                   callsign: :todo, decision: :todo }, states(review))
    assert_equal :callsign, review.first_actionable.key
  end

  test "more-handles hold waits on the applicant and falls through to the decision" do
    review = stages_for(:handle_check, status: ProspectiveApplication::STATUS_MORE_HANDLES)

    assert_equal :waiting, states(review)[:callsign]
    assert_equal :decision, review.first_actionable.key
  end

  test "PII hold waits while info is missing and becomes actionable once resolved" do
    held = stages_for(:handle_check, status: ProspectiveApplication::STATUS_HOLD_PII_ISSUE,
                                     approved_handle: "Moonbeam", phone: "")
    assert_equal :waiting, states(held)[:personal_info]
    assert_includes held.stages.find { |stage| stage.key == :personal_info }.summary, "Telephone number"

    resolved = stages_for(:handle_check, status: ProspectiveApplication::STATUS_HOLD_PII_ISSUE,
                                         approved_handle: "Moonbeam")
    assert_equal :todo, states(resolved)[:personal_info]
    assert_equal :personal_info, resolved.first_actionable.key
    assert_equal :done, states(resolved)[:callsign]
  end

  test "post-decision states collapse everything" do
    { ProspectiveApplication::STATUS_APPROVED => "Approved — awaiting account creation",
      ProspectiveApplication::STATUS_CREATED => "Approved — the account was created",
      ProspectiveApplication::STATUS_REJECT_UBERBONKED => "Uberbonked",
      ProspectiveApplication::STATUS_DUPLICATE => "Duplicate" }.each do |status, summary|
      review = stages_for(:handle_check, status:, approved_handle: "Moonbeam")

      assert review.post_decision?, "#{status} should be post-decision"
      assert_nil review.first_actionable
      assert_equal :done, states(review)[:decision]
      assert_equal summary, review.stages.last.summary
    end
  end

  test "open? is true only for the first actionable stage" do
    review = stages_for(:pending_qualified)

    assert review.open?(review.stages[1])
    assert_not review.open?(review.stages[0])
    assert_not review.open?(review.stages[4])
  end
end
