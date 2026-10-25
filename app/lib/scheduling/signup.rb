# frozen_string_literal: true

require "ostruct"

module Scheduling
  # The deep module that owns the scheduling-WRITE intake. Its public surface is two
  # intention-revealing calls -- +add+ and +remove+ -- each returning exactly one closed
  # Scheduling::Verdict (wrapped in a SignupResult carrier the controller dispatches on).
  #
  # Everything else -- the ~9 ordered gates, the ~11 Current reads, the capacity preview,
  # the locked store insert/delete and its post-success orchestration -- is hidden behind
  # those two methods as private internals, so each caller goes from orchestrating the
  # scattered Scheduling::Management surface to a single call.
  #
  # The present instant/year is read from Current (Current.year), the Groundhog-Day-aware
  # present, instead of Time.zone.now ad-hoc; the ActionLog ACTOR is Current.person, read
  # from that same request-scoped place.
  #
  # Collaborators it consumes (not folds in): Scheduling::Permission (the requirements
  # gate), Scheduling::SlotCapacity (the shared capacity rule), Scheduling::Query (the
  # enrollment helpers), and the Scheduling::ActiveRecordSlotStore write adapter.
  module Signup
    include Scheduling

    # Thin carrier the controller dispatches on. The closed Scheduling::Verdict is the
    # single source of truth for an operation's outcome: the controller branches on the
    # verdict's CLASS and the partials read the verdict's typed fields directly. This
    # carrier only retains the verdict plus its +#status+ (the existing Scheduling::STATUS_*
    # string) for the controller's unknown-status fallback.
    #
    # compute_signups reuses SignupResult as a mutable write-preview struct (status plus
    # the four capacity fields), so those accessors stay attribute-mutable; the capacity
    # characterization test builds a bare SignupResult through that path.
    class SignupResult
      attr_accessor :status,
                    :combined_max,
                    :linked_slots_became_full,
                    :is_full,
                    :linked_slots

      attr_reader :verdict

      def initialize(status = nil)
        @status = status if status
      end

      # Wrap a verdict for the controller: keep the verdict for type-dispatch and expose
      # its #status for the unknown-status fallback. No verdict field is flattened onto an
      # accessor -- the partials read the verdict's typed fields themselves.
      def self.from(verdict)
        result = new
        result.instance_variable_set(:@verdict, verdict)
        result.status = verdict.status
        result
      end
    end

    module_function

    # Sign +person+ up for +slot+. Returns a SignupResult wrapping exactly one of
    # Verdict::{NoPosition, AlreadyExists, MissingRequirements, MultipleEnrollment,
    # OutsideWindow, Full, Accepted}.
    def add(person, slot, want_to_force = false)
      SignupResult.from(decide_add(person, slot, want_to_force))
    end

    # Remove +person+ from +slot+. Returns a SignupResult wrapping exactly one of
    # Verdict::{OutsideWindow, Removed, MissingSignup, Failed}.
    def remove(person, slot, want_to_force = false)
      SignupResult.from(decide_remove(person, slot, want_to_force))
    end

    # Decides the outcome of adding +person+ to +slot+, returning exactly one
    # Scheduling::Verdict carrying only that branch's fields. Side effects
    # (ActionLog, mailers, slot.reload) happen at the same points as before; the
    # verdict is constructed at each existing return/finish point.
    def decide_add(person, slot, want_to_force)
      # You must hold the position
      unless PersonPosition.have_position?(person.id, slot.position_id)
        return Scheduling::Verdict::NoPosition.new(position_title: slot.position.title)
      end

      if PersonSlot.have_slot?(person.id, slot.id)
        return Scheduling::Verdict::AlreadyExists.new
      end

      trainer_forced = false
      enrollments = nil
      is_multiple_enrolled = false
      log_data = { slot_id: slot.id }
      year = Current.year

      # Check if schedule change can be forced
      can_force, is_trainer = can_force_schedule_change(slot, true)
      confirm_force = can_force ? want_to_force : false

      # Check various requirements before being allowed to sign up
      permission = Scheduling::Permission.new(person, year)

      unless confirm_force
        is_training = (slot.position_id == Position::TRAINING)
        allowed = is_training ? permission.training_signups_allowed : permission.all_signups_allowed

        unless allowed
          return Scheduling::Verdict::MissingRequirements.new(
            requirements: permission.requirements,
            may_force: can_force,
            training_signups_allowed: permission.training_signups_allowed
          )
        end
      end

      prevent_multiple_enrollments = slot.position.prevent_multiple_enrollments

      if slot.training? && prevent_multiple_enrollments
        can_join, found_enrollments = Scheduling::Query.can_join_training_slot?(person.id, slot)
        unless can_join
          is_multiple_enrolled = true
          trainer_forced = is_trainer
          enrollments = found_enrollments
        end
      elsif slot.position_id == Position::ALPHA && prevent_multiple_enrollments
        has_multiple, found_enrollments = Scheduling::Query.multiple_enrollments?(person.id, Position::ALPHA, slot.begins.year)
        if has_multiple
          is_multiple_enrolled = true
          enrollments = found_enrollments
        end
      end

      if is_multiple_enrolled && !confirm_force
        log_data[:multiple_enrollment] = true
        log_data[:enrolled_slot_ids] = enrollments.pluck(:id)

        ActionLog.record(Current.person, "person-slot-add-fail", "multiple enrollment attempt", log_data, person.id)

        return Scheduling::Verdict::MultipleEnrollment.new(
          slots: enrollments,
          may_force: (true if can_force)
        )
      end

      did_sign_sandman_affidavit = false
      position_id = slot.position_id
      is_sandman_shift = [Position::SANDMAN_TRAINING, Position::SANDMAN, Position::SANDMAN_TRAINER].include?(position_id)

      if is_sandman_shift
        person_event = PersonEvent.find_or_initialize_by(person_id: person.id, year:)
        did_sign_sandman_affidavit = Agreements.did_sign_document?(person, Document::SANDMAN_AFFIDAVIT_TAG, person_event)

        if !did_sign_sandman_affidavit && !confirm_force
          return Scheduling::Verdict::MissingRequirements.new(
            requirements: [Scheduling::MISSING_SIGNED_SANDMAN_AFFIDAVIT],
            may_force: can_force,
            training_signups_allowed: permission.training_signups_allowed
          )
        end
      end

      if slot.position.mvr_signup_eligible
        person_event = PersonEvent.find_by(person_id: person.id, year:)
        is_mvr_eligible = VehicleEligibility.is_mvr_eligible?(person.id, person_event, year)
      else
        is_mvr_eligible = false
      end

      is_forcing = confirm_force && can_force
      if slot.has_started && !is_forcing
        return Scheduling::Verdict::OutsideWindow.new(ended: slot.has_ended, may_force: false)
      end

      preview = compute_signups(slot, SignupResult.new, is_forcing)
      unless preview.status == Scheduling::STATUS_SUCCESS
        # The only non-success preview status today is STATUS_FULL.
        return Scheduling::Verdict::Full.new(may_force: nil)
      end

      # Go try to add the person to the slot/session
      schedule_result = create_signup(person.id, slot, force: is_forcing)

      if schedule_result != Scheduling::STATUS_SUCCESS
        may_force = (true if Scheduling::MAY_FORCE_STATUSES.include?(schedule_result) && can_force)
        return create_signup_failure_verdict(schedule_result, may_force)
      end

      log_data[:trainer_forced] = true if trainer_forced
      log_data[:multiple_enrollment] = true if is_multiple_enrolled
      log_data[:overcapacity] = true if preview.is_full
      log_data[:started] = true if slot.has_started
      log_data[:unsigned_sandman_affidavit] = true if is_sandman_shift && !did_sign_sandman_affidavit

      ActionLog.record(Current.person, "person-slot-add", nil, log_data, person.id)

      # Notify the person about the Training signing up
      if slot.training? && !slot.has_started
        #      TrainingSignupEmailJob.perform_later(person, slot, delay: 5.minutes)
      end

      signed_up = slot.reload.signed_up

      # Is the training slot at capacity? A plain slot's preview only says full when
      # forced past it, so the count after this sign-up decides.
      if slot.training? && (preview.is_full || signed_up >= preview.combined_max) && !slot.has_started && slot.position.contact_email.present?
        TrainingSessionFullMailer.with(sender_id: Current.person_id)
                                 .notify(slot:, signed_up:, notify_email: slot.position.contact_email).deliver_later
      end

      mvr = nil
      if slot.position.mvr_signup_eligible && !is_mvr_eligible
        deadline, past_deadline = VehicleEligibility.retrieve_mvr_deadline
        mvr = Scheduling::Verdict::MvrInfo.new(
          deadline: deadline,
          past_deadline: past_deadline,
          signed_motorpool_agreement: person_event&.signed_motorpool_agreement
        )
      end

      Scheduling::Verdict::Accepted.new(
        is_full: preview.is_full,
        combined_max: preview.combined_max,
        linked_slots: preview.linked_slots,
        linked_slots_became_full: preview.linked_slots_became_full,
        signed_up: signed_up,
        mvr: mvr,
        has_started: slot.has_started ? true : false,
        multiple_enrollment: is_multiple_enrolled,
        unsigned_sandman_affidavit: (is_sandman_shift && !did_sign_sandman_affidavit)
      )
    end

    # Decides the outcome of removing +person+ from +slot+, returning exactly one
    # Scheduling::Verdict.
    def decide_remove(person, slot, want_to_force)
      can_force, _ = can_force_schedule_change(slot, false)
      confirm_force = can_force ? want_to_force : false

      if slot.has_started && !confirm_force
        return Scheduling::Verdict::OutsideWindow.new(ended: slot.has_ended, may_force: can_force)
      end

      case (status = delete_signup(person.id, slot))
      when Scheduling::STATUS_SUCCESS
        Scheduling::Verdict::Removed.new
      when Scheduling::STATUS_MISSING_SIGNUP
        Scheduling::Verdict::MissingSignup.new
      else
        Scheduling::Verdict::Failed.new(status: status)
      end
    end

    # Maps a non-success create_signup status onto a verdict. STATUS_FULL renders as
    # the Full verdict (preserving the may_force decoding); STATUS_EXISTS as the
    # AlreadyExists verdict; anything else (e.g. db-failure) as Failed, which the
    # controller's else-branch renders as "Unknown status [...]".
    def create_signup_failure_verdict(status, may_force)
      case status
      when Scheduling::STATUS_FULL
        Scheduling::Verdict::Full.new(may_force: may_force)
      when Scheduling::STATUS_EXISTS
        Scheduling::Verdict::AlreadyExists.new
      else
        Scheduling::Verdict::Failed.new(status: status)
      end
    end

    # Internal delete entry point shared with Scheduling::Signup::Bulk. Runs the locked
    # store delete and -- on success only -- the same post-success orchestration
    # (parent/child recompute, empty-slot alerts, audit log) in the same order as before.
    def delete_signup(person_id, slot, reason: nil, forced: false)
      status = slot_store.delete_signup(person_id, slot, reason: reason)

      if status == Scheduling::STATUS_SUCCESS
        Scheduling::Query.adjust_parent_child_signups([slot])
        Scheduling::EmailNotification.handle_empty_signups_alerts(slot, person_id)
        # slot_id is what makes the removal answerable later: ScheduleLog and the
        # shift drop report both key on it, and a row without one groups under nil
        # and is invisible to both. Every other writer of this event records it.
        data = { slot_id: slot.id }
        data[:forced] = true if forced
        ActionLog.record(Current.person, "person-slot-remove", reason, data, person_id)
      end

      status
    end

    def create_signup(person_id, slot, force: false)
      slot_store.insert_signup(person_id, slot.id, force: force)
    end

    def slot_store
      Scheduling::ActiveRecordSlotStore.new
    end

    # Computes the signups for the slot based on the operation and force flag.
    #
    # @param slot [Slot]
    # @param result [SignupResult]
    # @param force [Boolean] whether to force the signup (ignoring limits)
    def compute_signups(slot, result, force)
      preview = Scheduling::SlotCapacity.new(slot).preview_add(force: force)

      result.status = preview.status
      result.is_full = preview.is_full
      result.combined_max = preview.combined_max
      result.linked_slots = preview.linked_slots
      result.linked_slots_became_full = preview.linked_slots_became_full

      result
    end

    def can_force_schedule_change(slot, is_signup = true)
      is_trainer = false
      role_can_force = nil

      if slot.training?
        if slot.art?
          position_id = slot.position_id

          # Check to see if the slot is a trainer slot
          # Position::TRAINERS is { trainee_position_id => [trainer_position_ids] }
          Position::TRAINERS.each do |trainee_position, trainer_positions|
            if trainer_positions.include?(position_id)
              # yup it is, use the trainee position for permission gating.
              position_id = trainee_position
              break
            end
          end

          role_can_force = Role::ART_TRAINER_BASE | position_id
          is_trainer = true
        elsif is_signup
          # Per TA 2023 - T.A. cadre members now only have the Trainer role, all other trainers have Training Seasonal.
          # Allow the real Training role to force add trainees.
          if Current.has_role?(Role::TRAINER)
            return [true, true]
          end
        else
          # Per request from TA 2020 - In-Person Trainers may NOT manually add trainees BUT
          # are allowed to remove trainees.
          role_can_force = [Role::TRAINER, Role::TRAINER_SEASONAL]
          is_trainer = true
        end
      elsif slot.position_id == Position::ALPHA
        role_can_force = Role::MENTOR
      end

      if role_can_force && Current.has_role?(role_can_force)
        return [true, is_trainer]
      end

      [Current.has_role?(Role::ADMIN), false]
    end

    private_class_method :decide_add,
                         :decide_remove,
                         :create_signup_failure_verdict,
                         :delete_signup,
                         :create_signup,
                         :slot_store,
                         :compute_signups,
                         :can_force_schedule_change
  end
end
