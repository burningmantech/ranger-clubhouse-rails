# frozen_string_literal: true

# The trainer attendance report (Laravel TrainerAttendanceReport): everyone
# signed up to TEACH a training's sessions in a year, and whether they showed
# up (trainer_status: attended / pending / no-show).
#
# A trainer signs up to a trainer slot (Green Dot Trainer), not to the session
# slot (Green Dot Training) -- the two are paired by the house matching rule
# (Training::SessionList.trainer_slot_match?) so the report, the landing page,
# and the session page can never disagree about which trainer group taught
# which session. Upstream states the same window from the other side
# (session.begins within [trainer.begins - 1 hour, trainer.ends]); reusing the
# one shared rule is a deliberate delta, not drift.
#
# Deliberate deltas from upstream:
# - Inactive trainer slots are INCLUDED (upstream applies no active filter
#   here, unlike CapacityReport) -- an inactive slot people are still signed
#   up to is exactly what this report exists to surface.
# - Sessions are the training position's own slots, matching upstream; HQ Full
#   Training's refresher slots (Training.session_position_ids) are not folded
#   in.
class Training::TrainerAttendanceReport
  # One teaching sign-up: the trainer slot, the trainer position it was for,
  # the attendance status, and the session it teaches (for the page link).
  Row = Data.define(:slot, :position_title, :status, :session_slot_id)
  Trainer = Data.define(:person, :callsign, :rows) do
    def attended_count = rows.count { |row| row.status == TrainerStatus::STATUS_ATTENDED }
  end
  Result = Data.define(:trainers, :signup_count, :attended_count)

  # Shared across requests -- the array is frozen so a caller cannot mutate it.
  EMPTY = Result.new(trainers: [].freeze, signup_count: 0, attended_count: 0)

  class << self
    # @param position [Position] the training position
    # @param year [Integer]
    # @return [Result]
    def execute(position, year)
      trainer_position_ids = Position::TRAINERS[position.id] || []
      return EMPTY if trainer_position_ids.empty?

      # Ordered so that a trainer slot matching two overlapping sessions always
      # pairs to the earlier one rather than to whatever the DB returned first.
      sessions = Slot.for_position(position.id).for_year(year).ordered_by_begins.to_a
      return EMPTY if sessions.empty?

      slots = paired_trainer_slots(trainer_position_ids, year, sessions)
      return EMPTY if slots.empty?

      build_result(rows_by_person(slots))
    end

    private

    # The year's trainer slots that pair to a session, as
    # [Slot, session slot id] -- unpaired trainer slots are dropped (upstream
    # `continue`).
    def paired_trainer_slots(trainer_position_ids, year, sessions)
      Slot.for_position(trainer_position_ids).for_year(year)
          .includes(:position).ordered_by_begins
          .filter_map do |slot|
            session = sessions.find { |candidate| Training::SessionList.trainer_slot_match?(candidate, slot) }
            [slot, session.id] if session
          end
    end

    # { person id => [Row] }, rows in begins order. Statuses are read straight
    # from trainer_status by trainer_slot_id -- never Slot#trainer_status,
    # which is a computed-column reader shadowing the association.
    def rows_by_person(slots)
      slot_ids = slots.map { |(slot, _)| slot.id }
      signups = PersonSlot.where(slot_id: slot_ids).pluck(:slot_id, :person_id)
      statuses = TrainerStatus.where(trainer_slot_id: slot_ids)
                              .pluck(:trainer_slot_id, :person_id, :status)
                              .to_h { |trainer_slot_id, person_id, status| [[trainer_slot_id, person_id], status] }
      signed_up_by_slot = signups.group_by(&:first).transform_values { |pairs| pairs.map(&:last) }

      rows = Hash.new { |hash, person_id| hash[person_id] = [] }
      slots.each do |(slot, session_slot_id)|
        signed_up_by_slot.fetch(slot.id, []).each do |person_id|
          rows[person_id] << Row.new(slot:,
                                     position_title: slot.position.title,
                                     status: statuses.fetch([slot.id, person_id], TrainerStatus::STATUS_PENDING),
                                     session_slot_id:)
        end
      end
      rows
    end

    # Trainers sorted by callsign, case-insensitively (upstream strcasecmp).
    # A missing person still gets a row -- upstream's "Person #id" fallback
    # keeps a dangling sign-up visible instead of silently dropping it.
    def build_result(rows_by_person)
      people = Person.where(id: rows_by_person.keys).index_by(&:id)

      trainers = rows_by_person.map do |person_id, rows|
        person = people[person_id]
        Trainer.new(person:, callsign: person&.callsign || "Person ##{person_id}", rows:)
      end.sort_by { |trainer| trainer.callsign.downcase }

      Result.new(trainers:,
                 signup_count: trainers.sum { |trainer| trainer.rows.size },
                 attended_count: trainers.sum(&:attended_count))
    end
  end
end
