# frozen_string_literal: true

module SignInBlocker
  module_function

  # Check for any blockers for a person to sign in to a given position.
  #
  # @param person [Person]
  # @param position [Position]
  # @param check_times [Boolean] if true, check slot timing constraints
  # @param now [ActiveSupport::TimeWithZone] the instant the check is evaluated against, governing
  #   slot timing and the training year
  # @return [Array<Hash>]
  def check(person, position, check_times: false, now: Current.time)
    person_id = person.id
    position_id = position.id

    blockers = []

    # Must do a cheetah cub shift first.
    if (person.status == Person::INACTIVE_EXTENSION || person.status == Person::RETIRED) &&
       position.type != Position::TYPE_TRAINING && position.id != Position::CHEETAH_CUB
      blockers << { blocker: Timesheet::BLOCKED_NOT_CHEETAH_CUB }
    end

    # Are they trained for this position?
    check_for_training(person, position, blockers, now.year)

    if check_times && position.is_checkin_time_restricted
      check_slots(person_id, position_id, blockers, now)
    end

    # A person must have an employee id if working a paid position. For international volunteers who may worked
    # but not get paid, a dummy code of "0" is fine.
    if position.paycode.present? && person.employee_id.blank?
      blockers << { blocker: Timesheet::BLOCKED_NO_EMPLOYEE_ID }
    end

    # Sandman blocker - must be qualified
    if position_id == Position::SANDMAN
      if Setting.get_value(Setting::SANDMAN_REQUIRE_AFFIDAVIT)
        event = PersonEvent.find_for_person_year(person.id, now.year)
        unless event&.sandman_affidavit
          blockers << { blocker: Timesheet::BLOCKED_UNSIGNED_SANDMAN_AFFIDAVIT }
        end
      end

      within_years = Setting.get_value(Setting::SANDMAN_REQUIRE_PERIMETER_EXP_WITHIN_YEARS)
      if within_years.present?
        unless Timesheet.did_person_work_position?(person_id, within_years, Position::SANDMAN_QUALIFIED_POSITIONS)
          last_worked = Timesheet.person_last_worked_any_position(person_id, Position::SANDMAN_QUALIFIED_POSITIONS)
          blockers << { blocker: Timesheet::BLOCKED_NO_BURN_PERIMETER_EXP,
                        within_years: within_years,
                        last_worked: last_worked }
        end
      end
    end

    blockers
  end

  # Did the person work a shift within one hour or is still working?
  #
  # @param person_id [Integer]
  # @param now [ActiveSupport::TimeWithZone]
  # @return [Boolean]
  def have_previous_shift(person_id, now)
    Timesheet
      .where(person_id: person_id)
      .where_year("on_duty", now.year)
      .where("off_duty IS NULL OR off_duty >= ?", 1.hour.ago(now))
      .order(off_duty: :desc)
      .exists?
  end

  # Is the person trained for a position in a given year?
  #
  # @param person [Person]
  # @param position [Position]
  # @param blockers [Array<Hash>]
  # @param year [Integer]
  def check_for_training(person, position, blockers, year)
    return if position.no_training_required || position.type == Position::TYPE_TRAINING
    return if position.allow_echelon && person.status == Person::ECHELON

    # The person has to have passed dirt training
    unless Training.did_person_pass_for_year?(person, Position::TRAINING, year)
      blockers << {
        blocker: Timesheet::BLOCKED_NOT_TRAINED,
        position: {
          id: Position::TRAINING,
          title: "In-Person Training"
        }
      }
    end

    training_id = position.training_position_id
    # And check if person did pass the ART
    return if training_id.blank? || Training.did_person_pass_for_year?(person, training_id, year)

    blockers << {
      blocker: Timesheet::BLOCKED_NOT_TRAINED,
      position: {
        id: training_id,
        title: Position.retrieve_title(training_id)
      }
    }
  end

  # Check if the person is checking in at an appropriate time for any available slots.
  #
  # @param person_id [Integer]
  # @param position_id [Integer]
  # @param blockers [Array<Hash>]
  # @param now [ActiveSupport::TimeWithZone]
  def check_slots(person_id, position_id, blockers, now)
    timestamp = now.to_i
    year = now.year

    early_check_in = Setting.get_value(Setting::SHIFT_CHECK_IN_EARLY_PERIOD).to_i * 60
    late_check_in = Setting.get_value(Setting::SHIFT_CHECK_IN_LATE_PERIOD).to_i * 60

    upcoming = if early_check_in.positive?
                 Slot.where(position_id: position_id)
                     .where(active: true)
                     .where(begins_year: year)
                     .where("begins_time > ?", timestamp)
                     .order(:begins_time)
                     .first
               end

    in_progress = if late_check_in.positive?
                    Slot.where(position_id: position_id)
                        .where(active: true)
                        .where(begins_year: year)
                        .where("begins_time <= ?", timestamp)
                        .where("ends_time > ?", timestamp)
                        .order(begins_time: :desc)
                        .first
                  end

    # Might be an adhoc position with no set times.
    return if upcoming.blank? && in_progress.blank?

    is_early = upcoming.present? && timestamp < (upcoming.begins_time - early_check_in)
    is_late = in_progress.present? && timestamp > (in_progress.begins_time + late_check_in)

    # Made it under the wire.
    return if !is_late && in_progress.present?

    # Good person, you're not too early.
    return if !is_early && upcoming.present?

    # Previous shift -- don't worry about it.
    return if have_previous_shift(person_id, now)

    # When the person might be too late for the current shift and too early for the upcoming one,
    # report it as too early if it's 2 hours before, otherwise report it as too late.
    #
    # When the sign in is determined to be too late, check to see if a shift was worked within the
    # last hour. This handles the burn nights where people deployed on a perimeter go on a different
    # shift after the perimeter has dropped. (e.g., Burn Perimeter -> Dirt).

    two_hours = 2 * 3600

    # Too early, and/or too late. Figure out the one to use.
    if is_early && is_late
      if (timestamp - in_progress.begins_time) < two_hours
        # Two hours late!
        blockers << build_check_in_time_blocker(Timesheet::BLOCKED_TOO_LATE, in_progress, timestamp, late_check_in)
      elsif timestamp > (upcoming.begins_time - two_hours)
        # Two hours before is considered too EARLY!
        blockers << build_check_in_time_blocker(Timesheet::BLOCKED_TOO_EARLY, upcoming, timestamp, early_check_in)
      else
        blockers << build_check_in_time_blocker(Timesheet::BLOCKED_TOO_LATE, in_progress, timestamp, late_check_in)
      end
    elsif is_early
      blockers << build_check_in_time_blocker(Timesheet::BLOCKED_TOO_EARLY, upcoming, timestamp, early_check_in)
    else
      blockers << build_check_in_time_blocker(Timesheet::BLOCKED_TOO_LATE, in_progress, timestamp, late_check_in)
    end
  end

  # Build a blocker hash for check-in timing issues.
  #
  # @param blocker [String]
  # @param slot [Slot]
  # @param timestamp [Integer]
  # @param cutoff [Integer]
  # @return [Hash]
  def build_check_in_time_blocker(blocker, slot, timestamp, cutoff)
    distance = if blocker == Timesheet::BLOCKED_TOO_LATE
                 timestamp - slot.begins_time
               else
                 slot.begins_time - timestamp
               end

    blocked = {
      blocker: blocker,
      distance: (distance / 60.0).ceil,
      cutoff: (cutoff / 60.0).ceil,
      slot: {
        id: slot.id,
        begins: slot.begins.to_s,
        description: slot.description
      }
    }

    if blocker == Timesheet::BLOCKED_TOO_EARLY
      blocked[:allowed_in] = (((slot.begins_time - cutoff) - timestamp) / 60.0).ceil
    end

    blocked
  end
end
