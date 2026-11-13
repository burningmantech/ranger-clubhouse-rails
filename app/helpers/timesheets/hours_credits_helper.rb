# frozen_string_literal: true

# Helpers for the Hours & Credits ledger. Every name carries the report's own
# prefix: view helpers share one namespace across the whole application, so a
# plain name here would answer for every other page too.
module Timesheets::HoursCreditsHelper
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

  # A zero is a value and prints as a number, in a period column as in a total:
  # "—" would say nothing was recorded, which is not what a quiet part of the
  # season means.
  def hours_credits_hours(seconds) = hour_format(seconds.to_i)

  def hours_credits_credits(credits) = hours_credits_total_credits(credits)
end
