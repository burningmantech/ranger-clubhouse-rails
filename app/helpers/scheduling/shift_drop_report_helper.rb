# frozen_string_literal: true

module Scheduling::ShiftDropReportHelper
  # The windows upstream offers, labeled as it labels them.
  def shift_drop_hour_options
    ShiftDropReport::HOUR_OPTIONS.map { |hours| [pluralize(hours, "hour"), hours] }
  end

  # The window is not a narrowing filter with an "off" position -- it always
  # applies, and both pages state it in words -- so it draws a chip only once it
  # differs from the default. Removing the chip returns to the default rather
  # than to "no window", which is not a thing this report has, which is also why
  # default_url is the page's own clear-all target.
  def shift_drop_filter_chips(hours, default_url)
    return [] if hours == ShiftDropReport::DEFAULT_HOURS

    [{ label: "Dropped Within: #{pluralize(hours, "hour")} of start", url: default_url }]
  end

  # The index summary, which is also the answer for a reader who goes no
  # further. It names the window every time: the same page reads completely
  # differently at one hour and at forty-eight.
  def shift_drop_summary_count(summary)
    window = "within #{pluralize(summary.hours, "hour")} of shift start"
    return "No drops #{window}" if summary.drop_count.zero?

    "#{pluralize(summary.positions.size, "position")} · " \
      "#{pluralize(summary.slot_count, "shift")} · " \
      "#{pluralize(summary.drop_count, "drop")} #{window}"
  end

  # Offered only when there is somewhere to widen to. At the largest window the
  # select carries, "widen the window" is the single action the empty page
  # suggests and the one the reader cannot take.
  def shift_drop_widen_hint(hours)
    return "" if hours >= ShiftDropReport::HOUR_OPTIONS.max

    " Widen the window to look further back."
  end

  # Only the exception count, and nothing at all when the window is already
  # inside the threshold: asked for one hour, every drop is within two, and the
  # badge would do nothing but repeat the drop count on every row.
  def shift_drop_position_badges(position, hours)
    return [] unless hours > ShiftDropReport::URGENT_HOURS && position.urgent_count.positive?

    [ui_badge("#{position.urgent_count} within #{pluralize(ShiftDropReport::URGENT_HOURS, "hour")}",
              :error, size: "base")]
  end

  # slot_shift_time returns a <span>, so the pieces are joined rather than
  # interpolated -- interpolation hands safe_join a plain String and the markup
  # is escaped into the page.
  def shift_drop_shift(slot)
    parts = [slot_shift_time(slot)]
    parts << " · #{slot.description}" if slot.description.present?
    safe_join(parts)
  end

  # How much notice the shift got, in words. Upstream reports a decimal ("0.8"),
  # which is a number the reader has to convert before it means anything; the
  # export keeps that unit, the page says "48 min". Never color alone: the
  # urgent rows carry the icon and sit inside a badge.
  #
  # The badge is suppressed on the same rule the index badge uses: asked for a
  # window already inside the threshold, every drop is urgent, and marking all
  # of them red says nothing while reading as if the whole page were on fire.
  def shift_drop_notice(drop, hours)
    words = hour_minute_words(drop.seconds_before)
    return words unless drop.urgent? && hours > ShiftDropReport::URGENT_HOURS

    ui_badge(words, :error, icon: "triangle-exclamation", icon_type: :solid, size: "sm")
  end
end
