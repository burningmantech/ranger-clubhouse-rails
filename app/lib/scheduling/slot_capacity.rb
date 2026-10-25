# frozen_string_literal: true

require "ostruct"

module Scheduling
  # The one authoritative implementation of parent/child/trainer-multiplier slot
  # capacity math. Two faces of the same rule:
  #
  #   - fold (DISPLAY, no +1): how full a linked parent/child pair is right now.
  #     Used by Slot.retrieve_sign_ups and Query#adjust_parent_child_signups.
  #   - preview_add (WRITE-PREVIEW, +1): would adding one seat overflow, and did it
  #     just fill the last spot. Used by Management#compute_signups.
  #
  # A child cannot exceed its own max, nor cause combined(parent + child) to exceed the
  # parent's max. Trainer slots multiply their max by the trainer slot's signups.
  class SlotCapacity
    # The display fold (no +1). Given the parent-side and child-side raw counts and
    # maxes, returns [parent_display_count, child_display_count]: the parent absorbs
    # the child's count, and both clamp to their own max once the combined count
    # reaches the parent's max.
    def self.fold(parent_signed_up, child_signed_up, parent_max, child_max)
      if (parent_signed_up + child_signed_up) >= parent_max
        [parent_max, child_max]
      else
        [parent_signed_up + child_signed_up, child_signed_up]
      end
    end

    # Write-preview verdict consumed by Management#compute_signups.
    Preview = Data.define(:status, :is_full, :combined_max, :linked_slots, :linked_slots_became_full)

    # +slot+ must respond to: signed_up, max, parent_signup_slot, child_signup_slot,
    #   trainer_slot, trainer_slot_id.
    def initialize(slot)
      @slot = slot
    end

    # Effective max for a PLAIN/trainer slot (parent/child pairs use the fold instead).
    #
    # This is the SINGLE place that owns the whole trainer-multiplier rule: not just
    # the multiply, but the guard that decides WHETHER it applies. A slot without a
    # trainer slot has no multiplier (the count, whatever it is, is ignored); a slot
    # WITH one multiplies its base max by the trainer slot's current signup count
    # (0 trainers zeroes the capacity).
    #
    # The kernel does no I/O. WHERE the fresh trainer count comes from is the caller's
    # freshness contract, and each path has a different one:
    #   - write path:   under-lock re-read of the trainer row    (pass trainer_signed_up:)
    #   - query/display: a joined trainer_count column            (pass trainer_signed_up:)
    #   - in-memory:    the slot's loaded :trainer_slot assoc     (omit; resolved here)
    # Callers supply only the freshly-obtained VALUE; the guard, the default lookup,
    # and the multiply all live here so the rule is tested and changed in one place.
    #
    # +trainer_signed_up+ is the caller's freshly-obtained trainer signup count, or
    # :unfetched to let the kernel read it off the in-memory association.
    def effective_max(trainer_signed_up: :unfetched)
      return @slot.max unless @slot.trainer_slot_id

      count = trainer_signed_up
      count = @slot.trainer_slot&.signed_up if count == :unfetched
      count ? @slot.max * count : @slot.max
    end

    # The +1 write-preview: would adding this seat be allowed, is the slot now full,
    # and (for linked pairs) did adding it just fill the parent. Mirrors the three
    # branches of the old compute_signups exactly.
    def preview_add(force:)
      sign_ups = @slot.signed_up
      own_max = @slot.max

      if (parent = @slot.parent_signup_slot)
        combined = sign_ups + parent.signed_up
        if (sign_ups >= own_max || combined >= parent.max) && !force
          return Preview.new(STATUS_FULL, true, own_max,
                             [OpenStruct.new(slot: parent, signed_up: combined)], false)
        end

        is_full = false
        adjusted_combined = combined + 1
        if (sign_ups + 1) >= own_max || adjusted_combined >= parent.max
          is_full = true
          adjusted_combined = parent.max
        end
        Preview.new(STATUS_SUCCESS, is_full, own_max,
                    [OpenStruct.new(slot: parent, signed_up: adjusted_combined, max: parent.max)],
                    (combined + 1) == parent.max)

      elsif (child = @slot.child_signup_slot)
        combined = sign_ups + child.signed_up
        if !force && (sign_ups >= own_max || combined >= own_max)
          return Preview.new(STATUS_FULL, true, own_max,
                             [OpenStruct.new(slot: child, signed_up: child.max)], false)
        end

        is_full = false
        child_count = child.signed_up
        if (combined + 1) >= own_max || (sign_ups + 1) >= own_max
          is_full = true
          child_count = child.max
        end
        Preview.new(STATUS_SUCCESS, is_full, own_max,
                    [OpenStruct.new(slot: child, signed_up: child_count, max: child.max)],
                    (combined + 1) == own_max)

      else
        max = effective_max
        if sign_ups >= max
          return Preview.new(STATUS_FULL, true, max, [], false) unless force

          return Preview.new(STATUS_SUCCESS, true, max, [], false)
        end
        Preview.new(STATUS_SUCCESS, false, max, [], false)
      end
    end
  end
end
