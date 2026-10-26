# frozen_string_literal: true

# How a date reads (design-content > Dates, Times and Prices). The day is never
# zero-padded, the year sits between the date and the time, and the clock is
# 24-hour:
#
#   Date and time                   Thu Jan 8 @ 14:30         datetime_format
#   Date and time in another year   Thu Jan 8, 2026 @ 14:30   datetime_format(year: true)
#   Date                            Jan 8, 2026               mdy_format
#   Day label                       Thu Jan 8                 wday_month_day_format
#   Day label in another year       Thu Jan 8, 2026           wday_month_day_format(year: true)
#   In running copy                 January 8                 month_day_format
#   Long form                       Thursday, January 8, 2026 mdy_format(full: true)
#   Long form with the time         ... 2026 @ 14:30          full_datetime_format
#   A chip with no room             Thu 1/8 14:30             short_datetime_format
#   Admin logs                      2026-01-08 14:30:00       log_time_format, LOG_TIME
#   CSV, printed forms              2026-01-08 14:30          CSV_TIME, ymd_format
#
# Code with no helpers to hand (lib, presenters, controllers) uses the
# constants below with strftime, so the format still lives here.
module DateTimeHelper
  MONTH_DAY_TIME = "%a %b %-d @ %H:%M"
  MONTH_DAY_TIME_YEAR = "%a %b %-d, %Y @ %H:%M"
  DAY_LABEL = "%a %b %-d"
  DATE = "%b %-d, %Y"
  LONG_DATE = "%A, %B %-d, %Y"
  HOUR_MINS = "%H:%M"
  HOUR_MIN_DAY = "%a @ %H:%M"
  # A shift on a chip: "Wed 9/2 17:29".
  SHORT_DAY_TIME = "%a %-m/%-d %H:%M"
  # Timestamps in CSV exports.
  CSV_TIME = "%Y-%m-%d %H:%M"
  # Timestamps in filter-bar chips. Same digits as CSV_TIME, kept apart so a
  # chip can change without touching every export.
  CHIP_TIME = "%Y-%m-%d %H:%M"
  # Timestamps on the admin log pages (action, bug report, error and request
  # logs). Rows land many to the second, and a page stamped only to the minute
  # cannot be read in order.
  LOG_TIME = "%Y-%m-%d %H:%M:%S"

  def datetime_format(start, finish = nil, tz: nil, tz_abbr: nil, year: false)
    return "" unless start

    timezone = tz || "America/Los_Angeles"
    display_abbr = tz_abbr ? " (#{tz_abbr})" : ""

    start_parsed = parse_time_in_zone(start, timezone)
    return start.to_s unless start_parsed

    unless finish
      return format_date(start_parsed, year ? MONTH_DAY_TIME_YEAR : MONTH_DAY_TIME, display_abbr)
    end

    end_parsed = parse_time_in_zone(finish, timezone)
    unless end_parsed
      return "#{format_date(start_parsed, year ? MONTH_DAY_TIME_YEAR : MONTH_DAY_TIME, display_abbr)} to #{finish}".html_safe
    end

    if year
      return "#{format_date(start_parsed, MONTH_DAY_TIME_YEAR, display_abbr)} to #{format_date(end_parsed, MONTH_DAY_TIME_YEAR, display_abbr)}".html_safe
    end

    if start_parsed.year != end_parsed.year
      return "#{format_date(start_parsed, MONTH_DAY_TIME_YEAR, display_abbr)} to #{format_date(end_parsed, MONTH_DAY_TIME_YEAR, display_abbr)}".html_safe
    end

    end_format = if start_parsed.day == end_parsed.day
                   HOUR_MINS
                 elsif (end_parsed.yday - start_parsed.yday) > 1
                   MONTH_DAY_TIME
                 else
                   HOUR_MIN_DAY
                 end

    "#{format_date(start_parsed, MONTH_DAY_TIME, display_abbr)} to #{format_date(end_parsed, end_format)}".html_safe
  end

  # A shift's window in the shift's own timezone. A slot carries one, and
  # rendering it in the app's zone shows a different clock time than the page
  # the shift was created on, with nothing to say which is meant -- so every
  # slot page passes tz/tz_abbr, and passes them from here rather than each
  # spelling the same call.
  def slot_shift_time(slot)
    datetime_format(slot.begins, slot.ends, tz: slot.timezone, tz_abbr: slot.timezone_abbr)
  end

  # A timestamp on an admin log page, to the second.
  def log_time_format(time)
    time&.in_time_zone(Time.zone)&.strftime(LOG_TIME).to_s
  end

  def full_datetime_format(date)
    return "" if date.blank?

    begin
      d = date.is_a?(String) ? Time.zone.parse(date) : date

      if d.nil?
        return "invalid date [#{date}]"
      end

      d.strftime("#{LONG_DATE} @ %H:%M")
    rescue
      "invalid date [#{date}]"
    end
  end

  def hour_minute_format(seconds)
    seconds = seconds.to_i
    minutes = (seconds / 60) % 60
    hours = seconds / 3600

    "%d:%02d" % [hours, minutes]
  end

  def hour_minute_words(seconds, full: false)
    seconds = seconds.to_i

    minutes = (seconds / 60) % 60
    hours = seconds / 3600

    time = "#{minutes} #{(full ? "minute" : "min").pluralize(minutes)}"
    if hours.positive?
      time = "#{hours} #{"hour".pluralize(hours)} #{"and " if full}#{time}"
    end

    time
  end

  def hour_format(seconds)
    seconds = seconds.to_i
    if seconds.zero?
      "0.00"
    else
      "%0.2f" % (seconds / 3600.0)
    end
  end

  # A span past a day, said in days and hours. hour_minute_words renders a
  # twelve-day gear checkout as "295 hours 20 min" and hour_minute_format as
  # "295:20", neither of which a reader can place. Callers pick their own
  # sub-day format and hand anything longer to this.
  def day_hour_format(seconds)
    seconds = seconds.to_i
    days = seconds / 1.day.to_i
    hours = (seconds % 1.day.to_i) / 1.hour.to_i

    "#{pluralize(days, "day")} #{pluralize(hours, "hour")}"
  end

  # The common pairing: a clock below a day, days and hours above. Every caller
  # that measures an open-ended span -- a checkout against now, a check-in
  # against a shift days away -- needs the same switch, so it lives here rather
  # than being spelled again beside each one.
  def hour_minute_or_day_format(seconds)
    (seconds < 1.day) ? hour_minute_format(seconds) : day_hour_format(seconds)
  end

  # The same switch for the pages that spell the sub-day span in words rather
  # than on a clock.
  def hour_minute_words_or_day_format(seconds)
    (seconds < 1.day) ? hour_minute_words(seconds) : day_hour_format(seconds)
  end

  # "July 4" — month and day in running copy (deadlines, holidays).
  def month_day_format(date)
    return "" if date.blank?

    d = date.is_a?(String) ? Time.zone.parse(date) : date
    d ? d.strftime("%B %-d") : ""
  rescue ArgumentError
    ""
  end

  # "Wed Jul 30" — compact day labels for schedule filters; "Wed Jul 30, 2025"
  # with year: where the page spans years.
  def wday_month_day_format(date, year: false)
    return "" if date.blank?

    d = date.is_a?(String) ? Time.zone.parse(date) : date
    d ? d.strftime(year ? "#{DAY_LABEL}, %Y" : DAY_LABEL) : ""
  rescue ArgumentError
    ""
  end

  # "Wed 9/2 17:29" — a shift where datetime_format's month name and @ do not
  # fit, as on a chip. The stored wall-clock time, as datetime_format prints it.
  def short_datetime_format(time)
    time ? time.strftime(SHORT_DAY_TIME) : ""
  end

  # "2026-08-08" — the unambiguous ordering printed forms use (upstream's
  # ymd-format helper).
  def ymd_format(date)
    return "" if date.blank?

    d = date.is_a?(String) ? Time.zone.parse(date) : date
    d ? d.strftime("%Y-%m-%d") : ""
  rescue ArgumentError
    ""
  end

  def mdy_format(date, full: false)
    return "" if date.blank?

    d = date.is_a?(String) ? Time.zone.parse(date) : date
    return "" unless d

    d.strftime(full ? LONG_DATE : DATE)
  rescue ArgumentError
    ""
  end

  private

  def parse_time_in_zone(time_value, timezone)
    return nil unless time_value

    tz = ActiveSupport::TimeZone[timezone]
    return nil unless tz

    # Keep the wall-clock time and stamp it with the timezone (dayjs .tz(tz, true));
    # a Time's to_s carries an offset, which tz.parse would honor and convert.
    value = time_value.respond_to?(:strftime) ? time_value.strftime("%F %T") : time_value.to_s
    tz.parse(value)
  rescue ArgumentError
    nil
  end

  def format_date(date, format, abbr = "")
    # The tooltip in the app's zone; the layout's local-time restates it in the browser's.
    local_time = date.in_time_zone(Time.zone).strftime("#{MONTH_DAY_TIME_YEAR} (%Z)")
    content_tag(:span, "#{date.strftime(format)}#{abbr}".html_safe, class: "inline-block", title: local_time,
                data: { local_time_target: "time", utc: date.utc.iso8601 })
  end
end
