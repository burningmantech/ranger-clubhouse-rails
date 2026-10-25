# frozen_string_literal: true

module Scheduling
  # Bulk-copies position credits into new credits with their times shifted by a
  # delta (the Ember ops/credits "Copy Credits" tool). Credits left behind by a
  # deleted position cannot be copied, mirroring the Ember rule.
  class PositionCreditCopier
    COPY_ATTRS = %w[position_id credits_per_hour description].freeze

    Result = Struct.new(:credits, :errors, keyword_init: true) do
      def success?
        errors.empty?
      end
    end

    class << self
      # Credits eligible for copying: the ones whose position still exists.
      def copyable_credits(year, position_id: nil)
        scope = PositionCredit.for_year(year)
                              .where(position_id: Position.select(:id))
                              .includes(:position)
        position_id ? scope.where(position_id:) : scope
      end

      # Credits whose position has been deleted. Listed on the credit pages so
      # they can still be edited or deleted, but never copied.
      def orphaned_credits(year, position_id: nil)
        scope = PositionCredit.for_year(year).where.not(position_id: Position.select(:id))
        position_id ? scope.where(position_id:) : scope
      end

      # Copies the eligible credits in +ids+, shifting each credit's times by
      # +delta+ (a hash of :days/:hours/:minutes integers). Optional
      # +new_position_id+ retargets the copies (single source position only).
      # All-or-nothing.
      def copy(year:, ids:, delta:, new_position_id: nil)
        sources = copyable_credits(year).where(id: ids).to_a
        return Result.new(credits: [], errors: ["Select at least one credit to copy."]) if sources.empty?

        if new_position_id.present? && sources.map(&:position_id).uniq.many?
          return Result.new(credits: [], errors: ["Multiple positions cannot be copied into a single position."])
        end

        created = []
        PositionCredit.transaction do
          sources.each do |source|
            credit = PositionCredit.new(source.attributes.slice(*COPY_ATTRS))
            credit.start_time = SlotCopier.adjust_time(source.start_time, delta)
            credit.end_time = SlotCopier.adjust_time(source.end_time, delta)
            credit.position_id = new_position_id if new_position_id.present?
            credit.save!
            created << credit
          end
        end

        Result.new(credits: created, errors: [])
      rescue ActiveRecord::RecordInvalid => e
        record = e.record
        label = record.description.presence || "credit"
        Result.new(credits: [], errors: ["Could not copy #{label}: #{record.errors.full_messages.join(" ")}"])
      end
    end
  end
end
