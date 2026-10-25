# frozen_string_literal: true

# Shift check in/out commands — start a shift, end a shift, correct the
# position on an on-duty entry, and delete an accidentally started shift.
#
# Ported from the Laravel TimesheetController signin/signoff/updatePosition/
# deleteMistake actions and the Ember shift-check-in-out component (staged in
# port/). Each command returns a Result whose +status+ the controllers dispatch
# on, mirroring the upstream API status strings as symbols.
module ShiftManage
  Result = Struct.new(:status, :blockers, :entry, :now_active, keyword_init: true)

  # Who may force a blocked check-in or position update. The single source for
  # both the enforcement (force_failure) and the UI affordance (blocked modal).
  FORCE_ROLES = [Role::ADMIN, Role::CAN_FORCE_SHIFT].freeze

  # Training positions offered for check-in; all other Training-type positions
  # are excluded unless the title marks the person as a trainer.
  CHECK_IN_TRAINING_POSITIONS = [
    Position::TOW_TRUCK_TRAINING,
    Position::TROUBLESHOOTER_TRAINING,
    Position::SANDMAN_TRAINING
  ].freeze

  # How recently a shift must have ended to be offered for resumption — the
  # same window SignInBlocker#have_previous_shift treats as "just worked".
  RESIGNIN_WINDOW = 1.hour

  # An operator-supplied check-in time, "HH:MM" on a 24-hour clock. Anchored
  # \A..\z, not ^..$ — ^$ match around newlines, so "12:00\n09:99" would pass.
  START_TIME_FORMAT = /\A([01]?\d|2[0-3]):([0-5]\d)\z/

  # How far back a supplied check-in time may reach. A time-of-day carries no
  # date, so "23:45" typed at 00:30 has to mean last night — this is what
  # bounds that reading, and what stops "23:45" typed at lunchtime from
  # silently opening a shift twenty hours ago.
  START_TIME_LOOKBACK = 12.hours

  class << self
    def can_force?(user)
      user.has_role?(FORCE_ROLES)
    end

    # Start a shift. A blocked check-in may be forced by a user holding Admin
    # or Force Shift Start, with a mandatory reason.
    #
    # start_time backdates the check-in to a recent "HH:MM" (the Rollcall
    # page's Set Time). It only ever reaches backwards — see check_in_time.
    def sign_in(person:, position_id:, user:, slot_id: nil, force: false, reason: nil,
                start_time: nil)
      on_duty = Timesheet.find_person_on_duty(person.id)
      return Result.new(status: :already_on_duty, entry: on_duty) if on_duty

      now, time_failure = check_in_time(start_time)
      return time_failure if time_failure

      # A backdated check-in can land inside a shift the Ranger already
      # finished, which find_person_on_duty cannot see because that shift is
      # closed. Left unchecked it doubles their hours and their credits. Only
      # backdated writes need this: a check-in stamped now cannot overlap a
      # closed shift unless one is open, and that is the guard above. The
      # sibling that also writes non-now timestamps, BulkSignInOut, checks the
      # same thing the same way.
      if start_time.present? && Timesheet.find_overlap_for_person(person.id, now, now)
        return Result.new(status: :start_time_overlaps)
      end

      position, blockers, failure = check_in_position(person, position_id, force: force,
                                                      user: user, reason: reason, now: now)
      return failure if failure

      entry = Timesheet.new(person_id: person.id, position_id: position.id,
                            slot_id: slot_id, on_duty: now)
      apply_force(entry, blockers, reason)
      entry.audit_reason = "sign in"
      entry.save!(validate: false)

      log = { position_id: entry.position_id, on_duty: entry.on_duty.to_s }
      log[:signin_force_reason] = reason if blockers.any?
      # Upstream sets this too, but assigns it before it rebuilds $log from
      # scratch, so it never reaches the record (TimesheetController::signin).
      # A backdated check-in is exactly the thing the log exists to surface,
      # so the port keeps the flag.
      log[:set_time] = true if start_time.present?
      TimesheetManagement.report_sign_in(TimesheetLog::SIGNON, entry, blockers.any?, blockers, log)
      TimesheetManagement.unconfirm_timesheet(entry, "new entry - signed in")

      Result.new(status: :success, entry: entry)
    end

    # End a shift. An inactive person going off duty on a non-training,
    # non-Cheetah-Cub shift is automatically converted back to active status.
    def sign_off(entry, user:)
      return Result.new(status: :already_signed_off, entry: entry) if entry.off_duty.present?

      entry.off_duty = Current.time
      entry.audit_reason = "signout"
      entry.save!(validate: false)
      entry.log(TimesheetLog::SIGNOFF, { position_id: entry.position_id, off_duty: entry.off_duty.to_s })
      TimesheetManagement.unconfirm_timesheet(entry, "signoff")

      Result.new(status: :success, entry: entry, now_active: convert_inactive_to_active(entry, user))
    end

    # Correct the position on a still on-duty entry. Subject to the same
    # held/eligible/blocker checks as a fresh check-in; the position change
    # itself is audit-logged by the Timesheet model.
    def update_position(entry, position_id:, user:, force: false, reason: nil)
      return Result.new(status: :not_on_duty) if entry.off_duty.present?

      position, blockers, failure = check_in_position(entry.person, position_id,
                                                      force: force, user: user, reason: reason)
      return failure if failure

      entry.position_id = position.id
      apply_force(entry, blockers, reason)
      entry.audit_reason = "position update while on duty"
      entry.save!(validate: false)

      Result.new(status: :success, entry: entry)
    end

    # Resume a shift that was ended by mistake — clears the off-duty time so
    # the same entry continues. Port of the PHP resignin action; the off-duty
    # change itself is audit-logged by the Timesheet model.
    def resignin(entry)
      return Result.new(status: :not_signed_off) if entry.off_duty.nil?

      on_duty = Timesheet.find_person_on_duty(entry.person_id)
      return Result.new(status: :already_on_duty, entry: on_duty) if on_duty

      entry.off_duty = nil
      entry.audit_reason = "re-signin"
      entry.save!(validate: false)
      TimesheetManagement.unconfirm_timesheet(entry, "re-signin")

      Result.new(status: :success, entry: entry)
    end

    # The entry the person most plausibly ended by mistake: this year's most
    # recent shift, signed off within the resignin window.
    def recently_signed_off_entry(person)
      Timesheet.for_person(person.id)
               .for_year(Current.year)
               .with_off_duty
               .where("off_duty >= ?", RESIGNIN_WINDOW.ago(Current.time))
               .includes(:position)
               .order(off_duty: :desc)
               .first
    end

    # Delete a shift that was started by mistake. Only a still on-duty entry
    # qualifies; the deletion itself is audit-logged by the Timesheet model.
    def delete_mistake(entry)
      return Result.new(status: :not_on_duty) if entry.off_duty.present?

      entry.audit_reason = "accidental creation"
      entry.destroy
      entry.log(TimesheetLog::DELETE_MISTAKE, { position_id: entry.position_id })

      Result.new(status: :success)
    end

    # The positions offered for check-in, most-used first — port of the Ember
    # shift-check-in-out constructor. Blockers ride along on each Position
    # (attr_accessor populated by retrieve_all_for_person).
    #
    # Self-serve: when any blocker-free positions exist, only those are
    # offered. promote_self additionally floats the NVO / DPW Ranger
    # positions for people who manage their own shifts.
    def position_options(person, self_serve:, promote_self: false)
      rows = PersonPosition.retrieve_all_for_person(person, include_eligibility: true)
                           .reject(&:not_timesheet_eligible)
                           .select { |position| offerable_position?(position) }

      if self_serve
        unblocked = rows.reject { |position| position.blockers.present? }
        rows = unblocked if unblocked.any?
      end

      promote(rows, Position::DIRT)
      promote(rows, Position::DIRT_SHINY_PENNY)
      if promote_self
        promote(rows, Position::DPW_RANGER)
        promote(rows, Position::NVO_RANGER)
      end

      rows
    end

    # Has the person passed In-Person (dirt) Training this year? Echelon
    # status counts as passed.
    def training_passed?(person)
      person.is_echelon? ||
        Training.did_person_pass_for_year?(person, Position::TRAINING, Current.year)
    end

    # An inactive person going off duty on a non-training, non-Cheetah-Cub
    # shift is automatically converted back to active. Returns true when the
    # conversion happened.
    #
    # Public because ending a shift is not only sign_off's business: the bulk
    # sign in/out page closes live shifts too, and a Ranger's status must not
    # depend on which page an HQ worker happened to use.
    #
    # The Laravel-shared schema carries no FK on person_id or position_id, so a
    # non-optional belongs_to still reads nil. Every interactive caller reaches
    # its entry through a known person, but the mass signout sweep takes
    # whatever is open -- and an orphaned row raised here AFTER off_duty was
    # already saved, 500ing the request mid-sweep with no flash and no record of
    # how far it got. There is no one to convert on such a row, so it simply is
    # not converted.
    def convert_inactive_to_active(entry, user)
      person = entry.person
      return false unless person&.status == Person::INACTIVE
      return false if entry.position.nil? ||
                      entry.position.type == Position::TYPE_TRAINING ||
                      entry.position_id == Position::CHEETAH_CUB

      old_status = person.status
      person.status = Person::ACTIVE
      person.audit_reason = "automatic status conversion"
      person.save!(validate: false)
      AutomaticActiveConversionMailer.with(sender_id: user.id)
                                     .notify(person: person, old_status: old_status,
                                             position_title: entry.position.title,
                                             worker_callsign: user.callsign).deliver_later
      true
    end

    private

    # The instant a check-in is stamped with. Without an override that is now;
    # with one it is the most recent past occurrence of "HH:MM".
    #
    # Most recent PAST occurrence, not "today at": Rollcall runs through the
    # burn and the shift list reaches four hours back, so at 00:30 the roster
    # still carries last night's shifts and "23:45" means forty-five minutes
    # ago. Reading it as today would put it in the future and refuse the only
    # time the operator can truthfully enter.
    #
    # The rollback is bounded by START_TIME_LOOKBACK so a mistyped time cannot
    # reach back a whole day. Crossing midnight can move the instant into the
    # previous year on New Year's Eve, and that is correct rather than a skew:
    # the blocker checks then read the year the shift actually started in.
    #
    # Returns [ActiveSupport::TimeWithZone, nil] or [nil, failure Result].
    def check_in_time(start_time)
      now = Current.time
      return [now, nil] if start_time.blank?

      match = START_TIME_FORMAT.match(start_time.to_s.strip)
      return [nil, Result.new(status: :invalid_start_time)] unless match

      at = now.change(hour: match[1].to_i, min: match[2].to_i)
      at -= 1.day if at > now
      return [nil, Result.new(status: :start_time_out_of_range)] if at < START_TIME_LOOKBACK.ago(now)

      [at, nil]
    end

    # Resolve and vet a position for check-in or position correction.
    # Returns [position, blockers, nil] when the action may proceed, or
    # [nil, nil, failure Result] when it may not.
    def check_in_position(person, position_id, force:, user:, reason:,
                          now: Current.time)
      position = Position.find_by(id: position_id)
      unless position && PersonPosition.have_position?(person.id, position.id)
        return [nil, nil, Result.new(status: :position_not_held)]
      end
      return [nil, nil, Result.new(status: :position_not_eligible)] if position.not_timesheet_eligible

      blockers = SignInBlocker.check(person, position, check_times: true, now: now)
      failure = blockers.any? ? force_failure(blockers, force, user, reason) : nil
      [position, blockers, failure]
    end

    def force_failure(blockers, force, user, reason)
      return Result.new(status: :blocked, blockers: blockers) unless force
      return Result.new(status: :force_not_allowed) unless can_force?(user)
      return Result.new(status: :missing_force_reason) if reason.blank?

      nil
    end

    def apply_force(entry, blockers, reason)
      return if blockers.empty?

      entry.was_signin_forced = true
      entry.signin_force_reason = reason
    end

    def offerable_position?(position)
      position.type != Position::TYPE_TRAINING ||
        position.title.match?(/trainer/i) ||
        CHECK_IN_TRAINING_POSITIONS.include?(position.id)
    end

    def promote(rows, position_id)
      index = rows.index { |position| position.id == position_id }
      rows.unshift(rows.delete_at(index)) if index
    end
  end
end
