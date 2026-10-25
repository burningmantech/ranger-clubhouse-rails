# frozen_string_literal: true

# Who completed training in each of the year's sessions (Laravel
# TrainingCompletedReport): one entry per session with the trainees who
# passed and the trainers who attended.
#
# Deliberate delta from upstream: upstream builds its session list from the
# passed trainee_status rows, so a session no one passed -- including one
# no one has scored yet -- silently vanishes from the report. Here the
# session list is the year's ACTIVE sessions that have ENDED, so an unscored
# session shows up with zero trainees instead of disappearing (decree
# 2026-08-01).
class Training::CompletedReport
  Session = Data.define(:slot, :trainees, :trainers)
  Result = Data.define(:sessions, :trainee_count, :trainer_count)

  class << self
    # @param position [Position] the training position
    # @param year [Integer]
    # @return [Result]
    def execute(position, year)
      session_position_ids = Training.session_position_ids(position.id)

      # has_ended reads ends_adjusted, a Ruby method rather than a column,
      # so the ended filter cannot ride along in the query.
      slots = Slot.for_position(session_position_ids)
                  .for_year(year)
                  .active
                  .ordered_by_begins
                  .to_a
                  .select(&:has_ended)

      return Result.new(sessions: [], trainee_count: 0, trainer_count: 0) if slots.empty?

      trainees = trainees_by_slot(slots)
      trainers = trainers_by_slot(slots, session_position_ids, year)

      sessions = slots.map do |slot|
        Session.new(slot:, trainees: trainees[slot.id] || [], trainers: trainers[slot.id] || [])
      end

      # Season totals count attendance, not people -- someone who passed two
      # sessions counts twice, same as upstream.
      Result.new(sessions:,
                 trainee_count: sessions.sum { |session| session.trainees.size },
                 trainer_count: sessions.sum { |session| session.trainers.size })
    end

    private

    # { slot id => [Person] } for everyone marked passed. A trainee who was
    # later removed from the roster still counts -- the pass is the record.
    def trainees_by_slot(slots)
      TraineeStatus.passed.where(slot_id: slots.map(&:id))
                   .includes(:person)
                   .group_by(&:slot_id)
                   .transform_values { |rows| by_callsign(rows.map(&:person)) }
    end

    # { slot id => [Person] } for the trainers who ATTENDED. Trainers teach
    # from their own slot, so the link back to the session is the shared
    # matching rule (Training::SessionList.trainer_slot_match?): the trainer
    # slot's description equals the session's exactly and it begins within
    # [session.begins - 1 hour, session.ends]. One session can match several
    # trainer slots (one per trainer position), hence the uniq.
    def trainers_by_slot(slots, session_position_ids, year)
      trainer_position_ids = session_position_ids.flat_map { |id| Position::TRAINERS[id] || [] }.uniq
      return {} if trainer_position_ids.empty?

      trainer_slots = Slot.for_position(trainer_position_ids).for_year(year).to_a
      return {} if trainer_slots.empty?

      attended = TrainerStatus.where(trainer_slot_id: trainer_slots.map(&:id),
                                     status: TrainerStatus::STATUS_ATTENDED)
                              .includes(:person)
                              .group_by(&:trainer_slot_id)

      slots.to_h do |slot|
        people = trainer_slots.filter_map do |candidate|
          attended[candidate.id] if Training::SessionList.trainer_slot_match?(slot, candidate)
        end

        [slot.id, by_callsign(people.flatten.map(&:person).uniq)]
      end
    end

    def by_callsign(people)
      people.sort_by { |person| person.callsign.to_s.downcase }
    end
  end
end
