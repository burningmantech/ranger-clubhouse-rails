# frozen_string_literal: true

# The trained-but-never-rangered report (Laravel TrainedNoWorkReport): people
# who completed a training in a year yet never rangered a shift requiring it.
# Meant to be run AFTER the event -- mid-season the timesheets simply have not
# been written yet, so everyone looks delinquent.
#
# "Completed" covers both sides of the classroom: trainees who PASSED a session
# and trainers who ATTENDED one they signed up to teach.
#
# Deliberate deltas from upstream:
# - Upstream's trainer merge is dead code: it joins person_slot.id to slot.id
#   (primary key to primary key) and trainer_status.slot_id to
#   trainer_status.trainer_slot_id (a row against itself), so it can only ever
#   return noise. Both conditions are corrected here -- sign-ups pair on
#   person_slot.slot_id, and attendance on trainer_status.trainer_slot_id --
#   which is what the surrounding code plainly intends (decree 2026-08-02).
# - Upstream returns callsign/status only. Each person here also carries the
#   qualifications that put them on the list (passed vs taught, and which
#   session), so the page can say WHY someone is listed rather than leaving a
#   trainer looking like an untrained no-show.
class Training::TrainedNoWorkReport
  # One reason a person counts as trained: :passed a session, or :taught one.
  # slot is the session in both cases -- for a trainer that is the session
  # their trainer slot taught, which is the page they would visit to check.
  Qualification = Data.define(:kind, :slot)
  Trainee = Data.define(:person, :qualifications) do
    def callsign = person.callsign
    def status = person.status
  end

  # people is always present; the flags explain an empty list. no_positions:
  # the training has no working positions at all (a half-configured position).
  # no_slots: nothing scheduled yet. no_trained: no one has passed or taught.
  # All three false with no people means the happy case -- everyone rangered.
  Result = Data.define(:people, :no_positions, :no_slots, :no_trained)

  class << self
    # @param position [Position] the training position
    # @param year [Integer]
    # @return [Result]
    def execute(position, year)
      working_ids = Training.working_position_ids(position)
      return empty(no_positions: true) if working_ids.empty?

      # Upstream computes these slot ids and then never uses them -- the query
      # is really asking "has the schedule been published?", so it asks that.
      return empty(no_slots: true) unless Slot.active.for_year(year).for_position(working_ids).exists?

      qualifications = qualifications_by_person(position, year)
      return empty(no_trained: true) if qualifications.empty?

      Result.new(people: build_people(qualifications, working_ids, year),
                 no_positions: false, no_slots: false, no_trained: false)
    end

    private

    def empty(no_positions: false, no_slots: false, no_trained: false)
      Result.new(people: [], no_positions:, no_slots:, no_trained:)
    end

    # { person id => [Qualification] }, each person's reasons in session order.
    def qualifications_by_person(position, year)
      qualifications = Hash.new { |hash, person_id| hash[person_id] = [] }

      passed(position, year).each { |person_id, slot| qualifications[person_id] << Qualification.new(kind: :passed, slot:) }
      taught(position, year).each { |person_id, slot| qualifications[person_id] << Qualification.new(kind: :taught, slot:) }

      qualifications.each_value { |list| list.sort_by! { |qualification| qualification.slot.begins } }
      qualifications
    end

    # [[person id, session Slot]] for everyone who passed one of the year's
    # sessions. Upstream requires the sign-up as well as the passing grade, so
    # a trainee_status left behind by a roster removal does not resurrect
    # someone; the pairs are intersected in Ruby to keep the query in
    # ActiveRecord rather than a hand-written composite join.
    def passed(position, year)
      slots = Slot.active.for_position(position.id).for_year(year).index_by(&:id)
      return [] if slots.empty?

      signed_up = PersonSlot.where(slot_id: slots.keys).pluck(:slot_id, :person_id).to_set

      TraineeStatus.passed.where(slot_id: slots.keys)
                   .pluck(:slot_id, :person_id)
                   .filter_map { |slot_id, person_id| [person_id, slots[slot_id]] if signed_up.include?([slot_id, person_id]) }
    end

    # [[person id, session Slot]] for the trainers who showed up to teach.
    # A trainer signs up to a TRAINER slot; the attendance record names both
    # that slot (trainer_slot_id) and the session it taught (slot_id), and the
    # session is what the page links to.
    def taught(position, year)
      trainer_position_ids = Position::TRAINERS[position.id]
      return [] if trainer_position_ids.blank?

      trainer_slot_ids = Slot.active.for_position(trainer_position_ids).for_year(year).ids
      return [] if trainer_slot_ids.empty?

      signed_up = PersonSlot.where(slot_id: trainer_slot_ids).pluck(:slot_id, :person_id).to_set
      attended = TrainerStatus.where(trainer_slot_id: trainer_slot_ids, status: TrainerStatus::STATUS_ATTENDED)
                              .pluck(:trainer_slot_id, :person_id, :slot_id)
                              .select { |trainer_slot_id, person_id, _| signed_up.include?([trainer_slot_id, person_id]) }

      sessions = Slot.where(id: attended.map(&:last).uniq).index_by(&:id)
      attended.filter_map { |_, person_id, slot_id| [person_id, sessions[slot_id]] if sessions[slot_id] }
    end

    # Trained people who still hold a Ranger status and have no timesheet that
    # year in any of the working positions, by callsign.
    def build_people(qualifications, working_position_ids, year)
      rangered = Timesheet.for_year(year)
                          .where(position_id: working_position_ids, person_id: qualifications.keys)
                          .distinct.pluck(:person_id)

      Person.where(id: qualifications.keys - rangered, status: Person::ACTIVE_STATUSES)
            .order(:callsign)
            .map { |person| Trainee.new(person:, qualifications: qualifications[person.id]) }
    end
  end
end
