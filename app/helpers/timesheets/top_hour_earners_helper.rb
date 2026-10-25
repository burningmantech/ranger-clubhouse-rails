# frozen_string_literal: true

# Every method here is prefixed. Helper names share one namespace across the
# whole app, so a bare `year_class` would answer for every other page too.
module Timesheets::TopHourEarnersHelper
  # The best year is marked three ways -- a tint, bolder text, and the Top Year
  # column naming it -- so the ranking still reads for anyone who cannot pick the
  # tint out.
  def top_hour_earners_year_class(row, year)
    "bg-primary/10 font-semibold" if row.top_year?(year)
  end

  # What the report is showing, said in the filter bar. When the limit has cut
  # the list, the number left off is named too -- "Showing 200 people" reads as
  # the whole answer when it can be a fraction of one.
  def top_hour_earners_count(report)
    return unless report.any?

    # pluralize would spell the total without its thousands separator, and a
    # bare "3000" is the number a reader has to stop and count.
    shown = if report.truncated?
              "#{number_with_delimiter(report.rows.size)} of " \
                "#{number_with_delimiter(report.total)} #{"person".pluralize(report.total)}"
            else
              pluralize(report.rows.size, "person")
            end

    "Showing #{shown} for #{EventYearSpan.in_words(report.start_year, report.end_year)}"
  end
end
