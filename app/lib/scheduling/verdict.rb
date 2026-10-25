# frozen_string_literal: true

module Scheduling
  # The closed set of outcomes for a single add_to_schedule / remove_from_schedule
  # operation. Exactly one verdict is constructed per operation, at the point the
  # code already returns/finishes, and each verdict carries ONLY the fields its
  # branch sets today.
  #
  # The ONLY cross-cutting method is +#status+, which always returns one of the
  # existing Scheduling::STATUS_* strings so REQUIREMENT_LABELS / MAY_FORCE_STATUSES
  # lookups and the turbo_stream rendering stay byte-identical.
  #
  # These types are intentionally FREE-STANDING under Scheduling (not nested inside
  # Scheduling::Management) so they can later be relocated into Scheduling::Signup
  # by a namespace move only -- call sites reference Scheduling::Verdict::X.
  module Verdict
    # Nested MVR detail carried by Accepted when the signup makes the person MVR
    # eligible.
    MvrInfo = Data.define(:deadline, :past_deadline, :signed_motorpool_agreement)

    # The signup succeeded.
    Accepted = Data.define(
      :is_full,
      :combined_max,
      :linked_slots,
      :linked_slots_became_full,
      :signed_up,
      :mvr,
      :has_started,
      :multiple_enrollment,
      :unsigned_sandman_affidavit
    ) do
      def initialize(is_full:, combined_max:, linked_slots:, linked_slots_became_full:, signed_up:,
                     mvr: nil, has_started: false, multiple_enrollment: false, unsigned_sandman_affidavit: false)
        super
      end

      def status = Scheduling::STATUS_SUCCESS
    end

    # The shift is full and cannot accept another signup.
    Full = Data.define(:may_force) do
      def status = Scheduling::STATUS_FULL
    end

    # The person has not met one or more signup requirements.
    MissingRequirements = Data.define(:requirements, :may_force, :training_signups_allowed) do
      def status = Scheduling::STATUS_MISSING_REQUIREMENTS
    end

    # The person is already enrolled in a conflicting slot.
    MultipleEnrollment = Data.define(:slots, :may_force) do
      def status = Scheduling::STATUS_MULTIPLE_ENROLLMENT
    end

    # The shift has started or ended and cannot be signed up for / removed.
    OutsideWindow = Data.define(:ended, :may_force) do
      def status = ended ? Scheduling::STATUS_HAS_ENDED : Scheduling::STATUS_HAS_STARTED
    end

    # The person does not hold the position.
    NoPosition = Data.define(:position_title) do
      def status = Scheduling::STATUS_NO_POSITION
    end

    # The person is already signed up for the shift.
    AlreadyExists = Data.define do
      def status = Scheduling::STATUS_EXISTS
    end

    # The signup was removed successfully.
    Removed = Data.define do
      def status = Scheduling::STATUS_SUCCESS
    end

    # The shift was not signed up for (attempted removal).
    MissingSignup = Data.define do
      def status = Scheduling::STATUS_MISSING_SIGNUP
    end

    # An unknown create_signup / delete_signup result (e.g. db-failure). Preserves
    # the raw status for the controller's else-branch.
    Failed = Data.define(:status)
  end
end
