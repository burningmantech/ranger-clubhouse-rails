# frozen_string_literal: true

# Helpers for the Hours & Credits ledger. Every name carries the report's own
# prefix: view helpers share one namespace across the whole application, so a
# plain name here would answer for every other page too.
module Timesheets::HoursCreditsHelper
  # Stands in for a zero inside the three period groups. A page of "0.00"s reads
  # as data the eye has to check; a rule reads as nothing to see, which is what a
  # ranger who did not turn out for that part of the season means.
  BLANK_VALUE = "—"

  def hours_credits_chips(filter_params, year)
    filter_chips(filter_params, { status: "Status", years: "Years" },
                 value_label: ->(key, value) {
                   (key == :years) ? pluralize(value.to_i, "year") : value
                 }) do |remaining, _key|
      timesheets_hours_credits_path(year:, **remaining)
    end
  end

  # The seasons-served counts a reader can pick from, fewest first, each
  # carrying how many rangers it would deliver. Only the counts the roster
  # actually holds are offered -- any other choice could only come back empty.
  def hours_credits_years_options(years, matching:)
    [UiComponents::FilterBarHelper::ALL_FILTER_OPTION] +
      years.map { |count| ["#{pluralize(count, "year")} (#{matching.fetch(count, 0)})", count.to_s] }
  end

  # Where the two boundaries fall. Said on the page because every number in the
  # three groups depends on them, and they move by a week or so from year to
  # year.
  def hours_credits_event_week(report)
    "#{wday_month_day_format(report.event_start)} to #{wday_month_day_format(report.event_end)}"
  end

  # Two decimals even at zero, so the pair of totals reads as one pair of
  # numbers and matches the export cell for cell. The shared short form drops to
  # a bare "0", which sits oddly beside an hours column showing "0.00".
  def hours_credits_total_credits(credits)
    "%.2f" % credits.to_f
  end

  def hours_credits_hours(seconds)
    seconds.to_i.zero? ? BLANK_VALUE : hour_format(seconds)
  end

  def hours_credits_credits(credits)
    credits.to_f.zero? ? BLANK_VALUE : credit_format_short(credits)
  end
end
