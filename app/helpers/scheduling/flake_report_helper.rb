# frozen_string_literal: true

module Scheduling::FlakeReportHelper
  # Never color alone: each status carries its own icon and word.
  def flake_report_flake_badge = ui_badge("Flake", :error, icon: "user-xmark", icon_type: :solid, size: "sm")

  def flake_report_rogue_badge = ui_badge("Rogue", :warning, icon: "user-plus", icon_type: :solid, size: "sm")

  # slot_shift_time returns a <span>, so every piece is joined rather than
  # interpolated -- interpolation hands safe_join a plain String and the markup
  # gets escaped into the page.
  def flake_report_shift(slot)
    parts = [slot_shift_time(slot)]
    parts << " · #{slot.description}" if slot.description.present?
    safe_join(parts)
  end

  # Where the flake was instead. A timesheet for this position would have
  # cleared the sign-up, so anything reported here is another position's.
  def flake_report_flake_detail(flake)
    return "No timesheet during this shift" unless flake.timesheet

    safe_join([flake.timesheet_position_title, " · ", flake_report_duty_times(flake.timesheet)])
  end

  # Every row says when the shift ended, or that it has not. Stating a closed
  # timesheet in the present tense ("On duty 06:00") made a position no one had
  # covered for hours read as covered.
  def flake_report_duty_times(timesheet)
    unless timesheet.off_duty
      return safe_join(["On duty since ", datetime_format(timesheet.on_duty), ", still out"])
    end

    safe_join(["On duty ", datetime_format(timesheet.on_duty, timesheet.off_duty)])
  end

  # A rogue is found by the slot link alone, so its timesheet can be for
  # another position, or fall outside the shift's own hours entirely. Both are
  # said out loud -- unlabeled, the row reads as if the person rangered this
  # shift. An open timesheet gets no duration: Timesheet#duration counts to
  # now, which for a past year is a span of months rather than a shift.
  def flake_report_rogue_detail(rogue)
    parts = []
    parts << "#{rogue.position_title} · " if rogue.position_title
    parts << flake_report_duty_times(rogue.timesheet)
    parts << " · #{hour_minute_words(rogue.timesheet.duration)}" if rogue.timesheet.off_duty
    parts << " · outside this shift's hours" if rogue.outside_shift
    parts << " · no sign-up"

    safe_join(parts)
  end

  # Only the exception counts, and nothing at all when a position has none.
  def flake_report_position_badges(position)
    badges = []
    if position.flake_count.positive?
      badges << ui_badge(pluralize(position.flake_count, "flake"), :error, size: "base")
    end
    if position.rogue_count.positive?
      badges << ui_badge(pluralize(position.rogue_count, "rogue"), :warning, size: "base")
    end
    if position.unstaffed_slot_count.positive?
      badges << ui_badge("#{position.unstaffed_slot_count} with no sign-ups", :warning, size: "base")
    end

    badges
  end
end
