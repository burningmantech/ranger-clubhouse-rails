# frozen_string_literal: true

# Radio checkout/collection accounting for the HQ window interface.
#
# Ported from the Ember clubhouse/utils/radio-accounting.js (staged in
# port/utils/radio-accounting.js): +accounting+ is radioAccounting() and
# +radio_todo+ is computeRadioTodo(). The upstream util itself mirrored,
# exactly, the radio getters and decision tree that previously lived on
# controllers/hq/shift.js and routes/hq/shift.js setupController.
module RadioAccounting
  module_function

  # shift_radios         - checked out radios that are NOT permanently assigned
  # event_radios         - checked out radios that ARE permanently assigned
  # collect_at_shift_end - event radios above the event radio_max limit, to be
  #                        collected at the end of the shift (0 when not over)
  # collect_count        - total radios to collect now (shift radios + over-max
  #                        event radios)
  # over_max             - event radios to collect when the person is finished
  #                        rangering the event (capped at radio_max)
  Result = Struct.new(:shift_radios, :event_radios, :collect_count,
                      :collect_at_shift_end, :over_max, :radio_max,
                      keyword_init: true) do
    # Total radios currently checked out — the shift page's radioCount getter.
    def radio_count
      shift_radios + event_radios
    end
  end

  # Compute the radio checkout/collection accounting for a person.
  #
  # @param assets_checked_out [Enumerable] the person's currently checked-out
  #   PersonAsset rows (each responds to +asset+, whose +type+ and
  #   +perm_assign+ are read — perm_assign marks an event radio)
  # @param radio_max [Integer] the event radio_max limit for the person
  # @return [Result]
  def accounting(assets_checked_out, radio_max)
    radios = assets_checked_out.select { |row| row.asset.type == Asset::TYPE_RADIO }
    shift_radios = radios.count { |row| !row.asset.perm_assign }
    event_radios = radios.count { |row| row.asset.perm_assign }

    collect_at_shift_end = event_radios > radio_max ? event_radios - radio_max : 0

    Result.new(
      shift_radios:,
      event_radios:,
      collect_count: shift_radios + collect_at_shift_end,
      collect_at_shift_end:,
      over_max: event_radios > radio_max ? radio_max : event_radios,
      radio_max:
    )
  end

  # Decide which radio-related todo task (if any) the person should be nagged
  # about, based on their on/off duty state, whether they have any more
  # scheduled shifts, and their current radio accounting.
  #
  # @param off_duty [Boolean] true when the person is NOT currently on duty
  # @param no_more_scheduled [Boolean] true when there are no more upcoming shifts
  # @param accounting [Result] result of RadioAccounting.accounting
  # @return [Symbol, nil] an HqTodo radio task key, or nil when none applies
  def radio_todo(off_duty:, no_more_scheduled:, accounting:)
    collect_count = accounting.collect_count
    event_radios = accounting.event_radios
    radio_max = accounting.radio_max

    unless off_duty
      # Person is currently on duty.
      return HqTodo::COLLECT_RADIO if collect_count.positive?
      return HqTodo::COLLECT_RADIO_IF_DONE if event_radios.positive? && no_more_scheduled

      return nil
    end

    # Person is off duty / starting a shift.
    if radio_max.positive?
      if collect_count.positive?
        # Person is above the event radio checkout limit and/or has a shift radio
        HqTodo::COLLECT_RADIO
      elsif no_more_scheduled && event_radios.positive?
        # Has radios, and has no more upcoming shifts.
        HqTodo::COLLECT_RADIO_IF_DONE
      elsif event_radios < radio_max
        # Below their event radio issue count,
        HqTodo::ISSUE_RADIO
      end
      # else, has an event radio, and still working - don't nag.
    elsif collect_count.positive?
      # Off duty with radios, and not event authorized?
      HqTodo::COLLECT_RADIO
    else
      # No radio - Give 'em one.
      HqTodo::ISSUE_RADIO
    end
  end
end
