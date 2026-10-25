# frozen_string_literal: true

# The training landing page's session list (Laravel
# TrainingSessionController#sessions + TrainingSession#retrieveTrainers).
#
# Returns the year's sessions for a training position, split into
# [in progress & upcoming, past]. A session that ended earlier today (in the
# slot's timezone) stays in the upcoming bucket until the next calendar day --
# a deliberate grace window so trainers can finish scoring the day's session.
#
# Each session carries its trainer groups: one group per trainer position in
# Position::TRAINERS, matched to a trainer slot whose description equals the
# session's EXACTLY and which begins within [session.begins - 1 hour,
# session.ends]. No matching slot for a position drops that group; no groups
# at all is the landing page's cue to explain the matching rule.
class Training::SessionList
  Session = Data.define(:slot, :trainer_groups)
  TrainerGroup = Data.define(:position_title, :trainers)
  Trainer = Data.define(:person, :is_lead)

  class << self
    # THE trainer-slot matching rule, shared with TrainingSession so the
    # landing table and the management page can never disagree: the
    # candidate's description equals the session's EXACTLY and it begins
    # within [session.begins - 1 hour, session.ends].
    # @param session_slot [Slot]
    # @param candidate [Slot]
    # @return [Boolean]
    def trainer_slot_match?(session_slot, candidate)
      candidate.description == session_slot.description &&
        candidate.begins.between?(session_slot.begins - 1.hour, session_slot.ends)
    end

    # @param position [Position] the training position
    # @param year [Integer]
    # @return [Array(Array<Session>, Array<Session>)] [upcoming, past]
    def execute(position, year)
      session_position_ids = Training.session_position_ids(position.id)

      slots = Slot.for_position(session_position_ids).for_year(year).ordered_by_begins.to_a

      trainer_groups = build_trainer_groups(slots, session_position_ids, year)
      sessions = slots.map { |slot| Session.new(slot:, trainer_groups: trainer_groups[slot.id]) }

      sessions.partition { |session| !session.slot.has_day_ended? }
    end

    private

    # One pass over the year's trainer slots and rosters instead of upstream's
    # per-session queries. Returns { session slot id => [TrainerGroup, ...] }.
    def build_trainer_groups(slots, session_position_ids, year)
      trainer_position_ids = session_position_ids.flat_map { |id| Position::TRAINERS[id] || [] }.uniq
      return slots.to_h { |slot| [slot.id, []] } if trainer_position_ids.empty?

      trainer_slots = Slot.for_position(trainer_position_ids).for_year(year).order(:id).to_a
      rosters = PersonSlot.where(slot_id: trainer_slots.map(&:id))
                          .includes(:person)
                          .group_by(&:slot_id)
      leads = TrainerStatus.where(slot_id: slots.map(&:id), is_lead: true)
                           .pluck(:slot_id, :person_id)
                           .to_set
      titles = Position.titles_by_id(trainer_position_ids)

      slots.to_h do |slot|
        groups = (Position::TRAINERS[slot.position_id] || []).filter_map do |trainer_position_id|
          trainer_slot = trainer_slots.find do |candidate|
            candidate.position_id == trainer_position_id && trainer_slot_match?(slot, candidate)
          end
          next unless trainer_slot

          people = (rosters[trainer_slot.id] || []).map(&:person).sort_by { |p| p.callsign.downcase }
          TrainerGroup.new(
            position_title: titles[trainer_position_id],
            trainers: people.map { |p| Trainer.new(person: p, is_lead: leads.include?([slot.id, p.id])) }
          )
        end

        [slot.id, groups]
      end
    end
  end
end
