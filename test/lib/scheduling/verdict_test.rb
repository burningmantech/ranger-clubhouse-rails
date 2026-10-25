# frozen_string_literal: true

require "test_helper"

# Pins the closed set of scheduling verdicts: every verdict reports exactly one of
# the existing Scheduling::STATUS_* strings via #status, and each verdict only
# carries (responds to) its own branch's fields. This is the closed-set guarantee
# that lets the controller dispatch on verdict TYPE instead of decoding 18 attributes.
class Scheduling::VerdictTest < ActiveSupport::TestCase
  V = Scheduling::Verdict

  test "Accepted reports success" do
    verdict = V::Accepted.new(
      is_full: false, combined_max: 5, linked_slots: [],
      linked_slots_became_full: false, signed_up: 2
    )
    assert_equal Scheduling::STATUS_SUCCESS, verdict.status
  end

  test "Accepted defaults the optional fields" do
    verdict = V::Accepted.new(
      is_full: false, combined_max: 5, linked_slots: [],
      linked_slots_became_full: false, signed_up: 2
    )
    assert_nil verdict.mvr
    assert_equal false, verdict.has_started
    assert_equal false, verdict.multiple_enrollment
    assert_equal false, verdict.unsigned_sandman_affidavit
  end

  test "Accepted carries a nested MvrInfo" do
    mvr = V::MvrInfo.new(deadline: "2026-08-01", past_deadline: false, signed_motorpool_agreement: true)
    verdict = V::Accepted.new(
      is_full: true, combined_max: 5, linked_slots: [],
      linked_slots_became_full: true, signed_up: 5, mvr: mvr
    )
    assert_equal "2026-08-01", verdict.mvr.deadline
    assert_equal false, verdict.mvr.past_deadline
    assert_equal true, verdict.mvr.signed_motorpool_agreement
  end

  test "Full reports full" do
    assert_equal Scheduling::STATUS_FULL, V::Full.new(may_force: true).status
  end

  test "MissingRequirements reports missing-requirements" do
    verdict = V::MissingRequirements.new(requirements: ["x"], may_force: false, training_signups_allowed: true)
    assert_equal Scheduling::STATUS_MISSING_REQUIREMENTS, verdict.status
  end

  test "MultipleEnrollment reports multiple-enrollment" do
    assert_equal Scheduling::STATUS_MULTIPLE_ENROLLMENT, V::MultipleEnrollment.new(slots: [], may_force: nil).status
  end

  test "OutsideWindow reports has-ended when ended" do
    assert_equal Scheduling::STATUS_HAS_ENDED, V::OutsideWindow.new(ended: true, may_force: false).status
  end

  test "OutsideWindow reports has-started when not ended" do
    assert_equal Scheduling::STATUS_HAS_STARTED, V::OutsideWindow.new(ended: false, may_force: false).status
  end

  test "NoPosition reports no-position" do
    assert_equal Scheduling::STATUS_NO_POSITION, V::NoPosition.new(position_title: "Dirt").status
  end

  test "AlreadyExists reports exists" do
    assert_equal Scheduling::STATUS_EXISTS, V::AlreadyExists.new.status
  end

  test "Removed reports success" do
    assert_equal Scheduling::STATUS_SUCCESS, V::Removed.new.status
  end

  test "MissingSignup reports missing-signup" do
    assert_equal Scheduling::STATUS_MISSING_SIGNUP, V::MissingSignup.new.status
  end

  test "Failed preserves the raw status it was constructed with" do
    assert_equal Scheduling::STATUS_DB_FAILURE, V::Failed.new(status: Scheduling::STATUS_DB_FAILURE).status
  end

  # --- closed-set field guarantee: each verdict only responds to its own fields ---

  test "Full only carries may_force" do
    full = V::Full.new(may_force: true)
    assert_respond_to full, :may_force
    assert_not_respond_to full, :requirements
    assert_not_respond_to full, :linked_slots
    assert_not_respond_to full, :slots
  end

  test "MissingRequirements only carries its own fields" do
    verdict = V::MissingRequirements.new(requirements: [], may_force: false, training_signups_allowed: true)
    assert_respond_to verdict, :requirements
    assert_respond_to verdict, :may_force
    assert_respond_to verdict, :training_signups_allowed
    assert_not_respond_to verdict, :linked_slots
    assert_not_respond_to verdict, :is_full
  end

  test "Accepted does not respond to may_force or requirements" do
    verdict = V::Accepted.new(
      is_full: false, combined_max: 1, linked_slots: [],
      linked_slots_became_full: false, signed_up: 1
    )
    assert_not_respond_to verdict, :may_force
    assert_not_respond_to verdict, :requirements
    assert_not_respond_to verdict, :position_title
  end

  test "NoPosition only carries position_title" do
    verdict = V::NoPosition.new(position_title: "Dirt")
    assert_respond_to verdict, :position_title
    assert_not_respond_to verdict, :may_force
  end

  # --- SignupResult carries the verdict, not a flattened property bag ---
  #
  # SignupResult.from is now a thin wrapper: it retains the verdict for the controller's
  # type-dispatch and exposes the verdict's #status for the unknown-status fallback. It
  # does NOT copy verdict fields onto legacy accessors -- the partials read the verdict's
  # typed fields directly (see Me::AvailableSignUpsControllerTest for the rendered-output
  # proof), so the closed verdict is the single representation of the outcome.

  test "SignupResult.from retains the verdict for type dispatch" do
    verdict = V::Accepted.new(
      is_full: true, combined_max: 6, linked_slots: [:a],
      linked_slots_became_full: true, signed_up: 4
    )
    result = Scheduling::Management::SignupResult.from(verdict)

    assert_equal verdict, result.verdict
    assert_equal Scheduling::STATUS_SUCCESS, result.status
  end

  test "SignupResult.from exposes each verdict's status for the fallback" do
    {
      V::MissingRequirements.new(requirements: [], may_force: true, training_signups_allowed: false) =>
        Scheduling::STATUS_MISSING_REQUIREMENTS,
      V::NoPosition.new(position_title: "Dirt") => Scheduling::STATUS_NO_POSITION,
      V::Failed.new(status: Scheduling::STATUS_DB_FAILURE) => Scheduling::STATUS_DB_FAILURE
    }.each do |verdict, status|
      result = Scheduling::Management::SignupResult.from(verdict)
      assert_equal status, result.status
      assert_equal verdict, result.verdict
    end
  end

  test "SignupResult.from does not flatten verdict fields onto the carrier" do
    result = Scheduling::Management::SignupResult.from(V::NoPosition.new(position_title: "Dirt"))
    # The carrier no longer carries a wide property bag; outcome fields live on the verdict.
    assert_not_respond_to result, :position_title
    assert_not_respond_to result, :requirements
    assert_not_respond_to result, :is_mvr_eligible
  end
end
