# frozen_string_literal: true

module Scheduling
  # Bulk-copies slots into new slots with their times shifted by a delta
  # (the Ember ops/slots "Copy Slots" tool). Trainer/parent/trainee links and
  # training linkage are never carried over to the copies.
  class SlotCopier
    COPY_ATTRS = %w[description max url timezone position_id].freeze

    Result = Struct.new(:slots, :errors, keyword_init: true) do
      def success?
        errors.empty?
      end
    end

    class << self
      # Slots eligible for copying. Training and mentor/mentee-linked slots
      # cannot be copied yet (mirrors the Ember rule).
      def copyable_slots(year, position_id: nil)
        scope = Slot.for_year(year)
                    .where(training_id: 0, trainee_slot_id: nil, trainer_slot_id: nil)
                    .includes(:position)
                    .ordered_by_begins
        position_id ? scope.for_position(position_id) : scope
      end

      # Default day shift: days between the source year's Labor Day and the
      # target year's.
      def default_delta_days(from_year, to_year = Current.year)
        (EventDate.first_monday_of_september(to_year).to_date -
          EventDate.first_monday_of_september(from_year).to_date).to_i
      end

      def adjust_time(time, delta)
        time + delta[:days].days + delta[:hours].hours + delta[:minutes].minutes
      end

      # Copies the eligible slots in +ids+, shifting each slot's times by
      # +delta+ (a hash of :days/:hours/:minutes integers). Optional
      # +new_position_id+ retargets the copies (single source position only),
      # +overrides+ replaces description/max/url, and +activate+ sets whether
      # the new slots arrive active. All-or-nothing.
      def copy(year:, ids:, delta:, new_position_id: nil, activate: false, overrides: {})
        sources = copyable_slots(year).where(id: ids).to_a
        return Result.new(slots: [], errors: ["Select at least one slot to copy."]) if sources.empty?

        if new_position_id.present? && sources.map(&:position_id).uniq.many?
          return Result.new(slots: [], errors: ["Multiple positions cannot be copied into a single position."])
        end

        created = []
        Slot.transaction do
          sources.each do |source|
            slot = Slot.new(source.attributes.slice(*COPY_ATTRS))
            slot.begins = adjust_time(source.begins, delta)
            slot.ends = adjust_time(source.ends, delta)
            slot.position_id = new_position_id if new_position_id.present?
            slot.assign_attributes(overrides)
            slot.active = activate
            slot.save!
            created << slot
          end
        end

        Result.new(slots: created, errors: [])
      rescue ActiveRecord::RecordInvalid => e
        record = e.record
        label = record.description.presence || "slot"
        Result.new(slots: [], errors: ["Could not copy #{label}: #{record.errors.full_messages.join(" ")}"])
      end
    end
  end
end
