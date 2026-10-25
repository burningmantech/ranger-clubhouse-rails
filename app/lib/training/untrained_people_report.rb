# frozen_string_literal: true

# The untrained-people report (Laravel TrainingUntrainedPeopleReport):
# everyone holding a shift sign-up that requires this training who is not
# trained yet, split by blocker. "No training sign-up" is the urgent group --
# nothing on their schedule will train them. "Not passed yet" holds a session
# sign-up without a passing grade, which mid-season usually just means the
# session has not happened.
#
# Deliberate deltas from upstream:
# - Upstream selects working positions with a raw training_position_id match,
#   which for In-Person Training finds nothing in this schema;
#   Training.working_position_ids (shared with trained-no-work) is the
#   authority instead.
# - Upstream shows an arbitrary session per not-passed person (last row of an
#   unordered query); here it is their latest by begins -- after a failed
#   first session, the pending re-take is the one that matters.
# - Upstream's taught-trainer exclusion joins person_slot only to re-derive
#   the sign-up that trainer_status already names; attendance is read
#   directly.
class Training::UntrainedPeopleReport
  NO_SIGNUP = "no_signup"
  NOT_PASSED = "not_passed"

  # Blocker wording shared by the badge, the filter choices, and the CSV.
  BLOCKER_LABELS = { NO_SIGNUP => "No training sign-up", NOT_PASSED => "Not passed yet" }.freeze

  # One blocked person: why (blocker), the session sign-up behind a
  # not-passed row (nil for no-signup; a TRAINER slot for a pending trainer),
  # and their shift sign-ups (Slots with positions preloaded) in start order.
  Row = Data.define(:person, :blocker, :training_slot, :shifts) do
    def callsign = person.callsign
    def email = person.email
  end

  # people is always present; the flags explain an empty list, checked in
  # order: no_positions (nothing requires this training), no_sessions (no
  # training or trainer slots scheduled), no_shifts (nothing to sign up for).
  Result = Data.define(:people, :no_positions, :no_sessions, :no_shifts)

  class << self
    # @param position [Position] the training position
    # @param year [Integer]
    # @return [Result]
    def execute(position, year)
      working_ids = Training.working_position_ids(position)
      return empty(no_positions: true) if working_ids.empty?

      # The year's sessions plus the trainer slots that teach them -- signing
      # up for either counts as having training on the schedule.
      # Training.session_position_ids folds in the HQ refresher pairing. A
      # season holds a few dozen of these, so they are held as the id-keyed
      # lookup every later step resolves against.
      trainer_position_ids = Array(Position::TRAINERS[position.id])
      session_slots = Slot.active.for_year(year)
                          .for_position(Training.session_position_ids(position.id) + trainer_position_ids)
                          .index_by(&:id)
      return empty(no_sessions: true) if session_slots.empty?

      shift_slots = Slot.active.for_year(year).for_position(working_ids)
      return empty(no_shifts: true) unless shift_slots.exists?

      taught_ids = taught_person_ids(session_slots.values, trainer_position_ids)
      not_passed = not_passed_sessions(session_slots, taught_ids)

      # Both shift loads stay filtered to their blocker group -- the union of
      # the two groups is a tiny slice of the season's sign-ups, so loading
      # all of them to partition in Ruby would read orders of magnitude more.
      enrolled = PersonSlot.where(slot_id: session_slots.keys).select(:person_id)
      no_signup = shifts_by_person(shift_slots) { |scope| scope.where.not(person_id: enrolled) }
      not_passed_shifts = shifts_by_person(shift_slots) { |scope| scope.where(person_id: not_passed.keys) }

      Result.new(people: build_rows(no_signup, not_passed, not_passed_shifts),
                 no_positions: false, no_sessions: false, no_shifts: false)
    end

    private

    def empty(no_positions: false, no_sessions: false, no_shifts: false)
      Result.new(people: [], no_positions:, no_sessions:, no_shifts:)
    end

    # { person id => [shift Slot] } in start order, positions preloaded. The
    # block narrows the sign-up scope to one blocker group's people.
    def shifts_by_person(shift_slots)
      yield(PersonSlot.where(slot_id: shift_slots.select(:id)))
        .includes(slot: :position)
        .group_by(&:person_id)
        .transform_values { |signups| signups.map(&:slot).sort_by(&:begins) }
    end

    # { person id => session Slot } for everyone signed up to train who has no
    # passing grade in any of the year's sessions, minus the trainers who
    # taught one. The passed-and-taught majority is excluded in SQL -- only
    # the blocked few come back as rows.
    def not_passed_sessions(session_slots, taught_ids)
      scope = PersonSlot.where(slot_id: session_slots.keys).where.not(
        person_id: TraineeStatus.passed.where(slot_id: session_slots.keys).select(:person_id)
      )
      scope = scope.where.not(person_id: taught_ids) if taught_ids.any?

      scope.pluck(:person_id, :slot_id)
           .group_by(&:first)
           .transform_values { |pairs| pairs.map { |_, slot_id| session_slots.fetch(slot_id) }.max_by(&:begins) }
    end

    # Trainers who showed up to teach are trained even without a trainee pass.
    def taught_person_ids(session_slots, trainer_position_ids)
      trainer_slot_ids = session_slots.select { |slot| trainer_position_ids.include?(slot.position_id) }.map(&:id)
      return [] if trainer_slot_ids.empty?

      TrainerStatus.where(trainer_slot_id: trainer_slot_ids, status: TrainerStatus::STATUS_ATTENDED)
                   .distinct.pluck(:person_id)
    end

    # Urgent blocker first, callsign within. A not-passed person without any
    # shift sign-up drops out here (upstream's final filter): their id never
    # joins not_passed_shifts.
    def build_rows(no_signup, not_passed, not_passed_shifts)
      people = Person.where(id: no_signup.keys + not_passed_shifts.keys).index_by(&:id)

      rows = no_signup.map do |person_id, shifts|
        Row.new(person: people.fetch(person_id), blocker: NO_SIGNUP, training_slot: nil, shifts:)
      end
      rows += not_passed_shifts.map do |person_id, shifts|
        Row.new(person: people.fetch(person_id), blocker: NOT_PASSED,
                training_slot: not_passed.fetch(person_id), shifts:)
      end
      rows.sort_by { |row| [(row.blocker == NO_SIGNUP) ? 0 : 1, row.callsign.downcase] }
    end
  end
end
