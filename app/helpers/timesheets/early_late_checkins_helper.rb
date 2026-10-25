# frozen_string_literal: true

module Timesheets::EarlyLateCheckinsHelper
  FILTER_CHIP_LABELS = { position_id: "Position", callsign: "Callsign", via: "Via" }.freeze

  # How the check-in was made. A shift started at HQ writes no creation log, so a
  # missing value is the ordinary case rather than a gap, and it is named as
  # such; the rest is the wording the person timesheet pages already use for the
  # same field.
  def check_in_via_label(via)
    via.blank? ? "check in" : timesheet_log_via_label(via)
  end

  # The same label said as a select option: sentence case, because "check in"
  # mid-list reads as an instruction rather than a name for how the row arrived.
  def check_in_via_option_label(param)
    via = param == EarlyLateCheckInReport::VIA_NONE ? nil : param

    check_in_via_label(via).upcase_first
  end

  # "All" carries no id, so it clears the filter by being the option without one.
  def check_in_position_options(positions)
    [["All positions", ""]] +
      positions.sort_by { |position| position.title.downcase }
               .map { |position| ["#{position.title} (#{position.total})", position.position_id] }
  end

  # Commonest first, each carrying its count -- there are only ever three of
  # these, and alphabetical would bury the ordinary case behind the two rare
  # ones. Built from the year's own vias, so a method nothing was entered by is
  # not offered as a choice that can only return nothing.
  def check_in_via_options(via_counts)
    [["All methods", ""]] +
      via_counts.sort_by { |via, count| [-count, via] }
                .map { |via, count| ["#{check_in_via_option_label(via)} (#{count})", via] }
  end

  def check_in_filter_chips(filters, positions, year)
    display = lambda do |key, value|
      case key
      when :position_id
        positions.find { |position| position.position_id == value }&.title
      when :via then check_in_via_option_label(value)
      else value
      end
    end

    filter_chips(filters, FILTER_CHIP_LABELS, value_label: display) do |remaining|
      timesheets_early_late_checkins_path(year:, **remaining)
    end
  end

  # How far outside the window, said as hours and minutes -- and in days once it
  # runs past one. A position whose shifts are days apart, an on-call slot among
  # them, produces real check-ins four weeks early, and "686:27" is not a span a
  # reader can place. Upstream says those in days too.
  #
  # The distance is carried in whole minutes, which is how upstream reports it.
  def check_in_distance(entry) = hour_minute_or_day_format(entry.distance * 60)

  # A blank limit switches its check off entirely, and the page has to say so:
  # "0 mins" reads as a limit of zero, which would flag every check-in rather
  # than none of them.
  #
  # Built rather than trimmed from hour_minute_words, which spells the minutes
  # even when there are none -- "more than 1 hour 0 mins before it starts" is a
  # sentence no one reads twice on purpose.
  def check_in_limit_words(seconds)
    return "switched off" unless seconds.positive?
    return pluralize(seconds / 3600, "hour") if (seconds % 3600).zero?

    hour_minute_words(seconds)
  end

  # An empty report is only a clean year for the checks that actually ran. Any
  # switched-off limit has to be named here, because the empty page never
  # renders the sections that would otherwise say so.
  def check_in_empty_message(report, year)
    off = []
    off << "early" unless report.early_period.positive?
    off << "late" unless report.late_period.positive?

    return "Every check-in in #{year} landed inside its window." if off.empty?
    if off.size == 2
      return "Both check-in limits are switched off, so no check-in is measured against its shift."
    end

    "The #{off.first} check-in limit is switched off. Every other check-in in " \
      "#{year} landed inside its window."
  end
end
