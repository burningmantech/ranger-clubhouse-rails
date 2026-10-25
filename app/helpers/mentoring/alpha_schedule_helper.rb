# frozen_string_literal: true

# Presentation for /mentoring/alpha-schedule: the index's day grouping and the
# shift labels both the index and the sheets print.
module Mentoring::AlphaScheduleHelper
  # Alpha shifts run in Day/Swing pairs, which is how the mentor cadre talks
  # about them, so the index groups by calendar day. Shifts arrive ordered by
  # begins, and group_by preserves that, so both levels come out sorted.
  #
  # @param shifts [Array<AlphaShiftRoster::Shift>]
  # @return [Hash{Date => Array<AlphaShiftRoster::Shift>}]
  def alpha_schedule_days(shifts)
    shifts.group_by { |shift| shift.slot.begins.to_date }
  end

  # A shift's own name. Deliberately the slot description verbatim rather than
  # a shortened form: descriptions are hand-entered ("Alpha Mentor Walk -
  # Sunday Swing"), so any prefix-stripping rule would mangle the first one
  # that breaks the pattern. Undescribed slots fall back to their start time.
  def alpha_shift_title(slot)
    slot.description.presence || datetime_format(slot.begins)
  end

  # The same name as plain words, for the places that cannot show markup: a
  # page title, a confirmation. The time above is built as markup, which those
  # places would print as tags.
  def alpha_shift_title_text(slot)
    slot.description.presence || full_datetime_format(slot.begins)
  end

  # Sign-ups against capacity, as a percentage for the card meter. Slots with
  # no maximum read as empty rather than dividing by zero.
  def alpha_shift_fill_percentage(shift)
    max = shift.slot.max.to_i
    return 0 unless max.positive?

    ((shift.signed_up.to_f / max) * 100).round
  end

  # Amber once a shift is at capacity: the meter alone would read as "done"
  # when it means "no room left".
  def alpha_shift_fill_variant(shift)
    shift.full? ? :warning : :primary
  end

  # The one-or-two letter mentor outcome the information sheet prints beside a
  # prior mentoring year (upstream's mentor-short-status helper).
  #
  # Upstream keys this map on "bonked", but the status PersonMentor actually
  # stores is "bonk" -- so upstream prints "P", "SB", and then the raw word
  # "bonk". Keyed on the real value here; reproducing the typo would print an
  # inconsistent sheet, not a faithful one.
  MENTOR_SHORT_STATUS = {
    PersonMentor::STATUS_PASS => "P",
    PersonMentor::STATUS_BONK => "B",
    PersonMentor::STATUS_SELF_BONK => "SB"
  }.freeze

  def mentor_short_status(status)
    MENTOR_SHORT_STATUS[status] || status
  end
end
