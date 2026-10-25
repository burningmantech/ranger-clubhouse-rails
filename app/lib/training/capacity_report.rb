# frozen_string_literal: true

# The training capacity report (Laravel TrainingSlotCapacityReport): one row
# per ACTIVE session in the year -- how full it is, who signed up (bucketed by
# their status AT the session's start time), pass counts, and trainer
# staffing -- plus season totals and the year's unique trainer count.
#
# Deliberate deltas from upstream:
# - Upstream tops up the veteran bucket with `ids.count - statuses.count`
#   AFTER already bucketing status-less people as veterans -- a double count.
#   Here the else-branch alone handles missing status history.
# - Pass counts are only meaningful once a session has ended (Row#scored);
#   the view and CSV render dashes before then, so Totals#passed/#not_passed
#   sum SCORED sessions only (decree 2026-08-01).
class Training::CapacityReport
  Row = Data.define(:slot, :signed_up, :filled, :scored, :pnv_count, :veteran_count,
                    :auditor_count, :passed, :not_passed, :trainer_count)
  Totals = Data.define(:max, :signed_up, :filled, :pnv_count, :veteran_count, :auditor_count,
                       :passed, :not_passed)
  Result = Data.define(:rows, :unique_trainers, :totals)

  # Prospective / Alpha bucket -- everyone still on the intake side of the
  # pipeline at session time, including the bonk statuses (upstream rule).
  PNV_STATUSES = [
    Person::ALPHA, Person::BONKED, Person::PAST_PROSPECTIVE,
    Person::PROSPECTIVE, Person::PROSPECTIVE_WAITLIST, Person::UBERBONKED
  ].freeze

  class << self
    # @param position [Position] the training position
    # @param year [Integer]
    # @return [Result]
    def execute(position, year)
      slots = Slot.for_position(Training.session_position_ids(position.id))
                  .for_year(year)
                  .active
                  .ordered_by_begins
                  .to_a

      # Live roster lists, not the signed_up counter -- the status buckets
      # derive from these ids, so the mix always sums to the signup count.
      rosters = ids_by_slot(PersonSlot.where(slot_id: slots.map(&:id))
                                      .pluck(:slot_id, :person_id))
      # Passed is scoped to people STILL signed up -- a scored trainee who was
      # later removed from the roster no longer counts (upstream join rule).
      passed_ids = ids_by_slot(TraineeStatus.passed.where(slot_id: slots.map(&:id))
                                            .pluck(:slot_id, :person_id))
                   .transform_values(&:to_set)

      trainer_counts, unique_trainers = count_trainers(position, slots, rosters, year)

      rows = slots.map do |slot|
        build_row(slot, rosters[slot.id] || [], passed_ids[slot.id] || Set.new,
                  trainer_counts[slot.id])
      end

      Result.new(rows:, unique_trainers:, totals: totals_for(rows))
    end

    private

    def build_row(slot, person_ids, passed_ids, trainer_count)
      signed_up = person_ids.size
      pnv_count, auditor_count, veteran_count = bucket_statuses(person_ids, slot.begins)
      passed = person_ids.count { |person_id| passed_ids.include?(person_id) }

      Row.new(slot:, signed_up:, filled: percent(signed_up, slot.max), scored: slot.has_ended,
              pnv_count:, veteran_count:, auditor_count:,
              passed:, not_passed: signed_up - passed, trainer_count: trainer_count || 0)
    end

    # [pnv, auditor, veteran] counts for the roster, judged by each person's
    # status when the session begins -- someone who converted to Active after
    # training still counts in the bucket they trained in. Missing status
    # history falls through to the veteran (Returning) bucket.
    def bucket_statuses(person_ids, begins)
      return [0, 0, 0] if person_ids.empty?

      statuses = PersonStatus.find_status_for_ids_time(person_ids, begins)
      pnv = auditor = veteran = 0

      person_ids.each do |person_id|
        case statuses[person_id]&.new_status
        when Person::AUDITOR
          auditor += 1
        when *PNV_STATUSES
          pnv += 1
        else
          veteran += 1
        end
      end

      [pnv, auditor, veteran]
    end

    # { session slot id => trainer signup count } plus the year's distinct
    # trainer headcount. One trainer group per position in Position::TRAINERS
    # for the REPORT's position (upstream rule -- refresher rows share the HQ
    # trainer list), matched by the shared landing-page rule: exact
    # description and begins within [session.begins - 1h, session.ends].
    # Sessions with no signups are skipped, matching upstream, and only
    # ACTIVE trainer slots count -- upstream's capacity report filters them,
    # unlike the landing list (SessionList), which shows inactive trainer
    # groups flagged. Deliberate difference, not drift.
    def count_trainers(position, slots, rosters, year)
      trainer_position_ids = Position::TRAINERS[position.id] || []
      counted_slots = slots.select { |slot| rosters[slot.id].present? }
      return [{}, 0] if trainer_position_ids.empty? || counted_slots.empty?

      trainer_slots = Slot.for_position(trainer_position_ids).for_year(year)
                          .active.order(:id).to_a
      trainer_rosters = ids_by_slot(PersonSlot.where(slot_id: trainer_slots.map(&:id))
                                              .pluck(:slot_id, :person_id))
      candidates_by_position = trainer_slots.group_by(&:position_id)

      unique_ids = Set.new
      counts = counted_slots.to_h do |slot|
        trainer_ids = trainer_position_ids.flat_map do |trainer_position_id|
          matched = (candidates_by_position[trainer_position_id] || []).find do |candidate|
            Training::SessionList.trainer_slot_match?(slot, candidate)
          end
          matched ? trainer_rosters.fetch(matched.id, []) : []
        end
        unique_ids.merge(trainer_ids)
        [slot.id, trainer_ids.size]
      end

      [counts, unique_ids.size]
    end

    def totals_for(rows)
      max = rows.sum { |row| row.slot.max }
      signed_up = rows.sum(&:signed_up)
      scored_rows = rows.select(&:scored)

      Totals.new(
        max:,
        signed_up:,
        filled: percent(signed_up, max),
        pnv_count: rows.sum(&:pnv_count),
        veteran_count: rows.sum(&:veteran_count),
        auditor_count: rows.sum(&:auditor_count),
        passed: scored_rows.sum(&:passed),
        not_passed: scored_rows.sum(&:not_passed)
      )
    end

    # { slot id => [person ids] } from plucked [slot_id, person_id] pairs.
    def ids_by_slot(pairs)
      pairs.group_by(&:first).transform_values { |rows| rows.map(&:last) }
    end

    # Rounded fill percentage; 0 when there are no seats (max can be zero).
    # Deliberately unclamped -- over-subscription is real and displayed.
    def percent(count, max)
      max.positive? ? (count * 100.0 / max).round : 0
    end
  end
end
