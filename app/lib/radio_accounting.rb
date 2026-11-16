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
  # event_radios         - checked out radios that ARE permanently assigned and
  #                        count against the event radio limit
  # granted_radios       - checked out radios that ARE permanently assigned and
  #                        come from a group the person has a radio group
  #                        provision for: outside the limit, never collected
  #                        as over it, still collected when the person is done
  # collect_at_shift_end - event radios above the event event_radio_count limit, to be
  #                        collected at the end of the shift (0 when not over)
  # collect_count        - total radios to collect now (shift radios + over-max
  #                        event radios)
  # over_max             - event radios to collect when the person is finished
  #                        rangering the event (capped at event_radio_count)
  Result = Struct.new(:shift_radios, :event_radios, :collect_count,
                      :collect_at_shift_end, :over_max, :event_radio_count, :granted_radios,
                      keyword_init: true) do
    # Total radios currently checked out — the shift page's radioCount getter.
    def radio_count
      shift_radios + event_radios + granted_radios
    end
  end

  # Compute the radio checkout/collection accounting for a person.
  #
  # @param assets_checked_out [Enumerable] the person's currently checked-out
  #   PersonAsset rows (each responds to +asset+, whose +type+ and
  #   +shift_only+ are read — a radio that is not shift-only is an event radio)
  # @param event_radio_count [Integer] the event event_radio_count limit for the person
  # @param granted_group_ids [Array<Integer>] the radio asset groups the person
  #   holds a radio group provision for
  # @return [Result]
  def accounting(assets_checked_out, event_radio_count, granted_group_ids: [])
    radios = assets_checked_out.select { |row| row.asset.type == Asset::TYPE_RADIO }
    shift_radios = radios.count { |row| row.asset.shift_only }
    kept = radios.reject { |row| row.asset.shift_only }
    granted_radios = kept.count { |row| granted_group_ids.include?(row.asset.asset_group_id) }
    event_radios = kept.size - granted_radios

    collect_at_shift_end = event_radios > event_radio_count ? event_radios - event_radio_count : 0

    Result.new(
      shift_radios:,
      event_radios:,
      collect_count: shift_radios + collect_at_shift_end,
      collect_at_shift_end:,
      over_max: event_radios > event_radio_count ? event_radio_count : event_radios,
      event_radio_count:,
      granted_radios:
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
    event_radio_count = accounting.event_radio_count
    kept_radios = event_radios + accounting.granted_radios

    unless off_duty
      # Person is currently on duty.
      return HqTodo::COLLECT_RADIO if collect_count.positive?
      return HqTodo::COLLECT_RADIO_IF_DONE if kept_radios.positive? && no_more_scheduled

      return nil
    end

    # Person is off duty / starting a shift.
    if event_radio_count.positive?
      if collect_count.positive?
        # Person is above the event radio checkout limit and/or has a shift radio
        HqTodo::COLLECT_RADIO
      elsif no_more_scheduled && kept_radios.positive?
        # Has radios, and has no more upcoming shifts.
        HqTodo::COLLECT_RADIO_IF_DONE
      elsif event_radios < event_radio_count
        # Below their event radio issue count,
        HqTodo::ISSUE_RADIO
      end
      # else, has an event radio, and still working - don't nag.
    elsif collect_count.positive?
      # Off duty with radios, and not event authorized?
      HqTodo::COLLECT_RADIO
    elsif no_more_scheduled && kept_radios.positive?
      # Holds a granted specialized radio, and has no more upcoming shifts.
      HqTodo::COLLECT_RADIO_IF_DONE
    else
      # No radio - Give 'em one.
      HqTodo::ISSUE_RADIO
    end
  end
end
