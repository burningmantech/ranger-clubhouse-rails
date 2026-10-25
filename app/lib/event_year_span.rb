# frozen_string_literal: true

# A span of event years, as the multi-year reports read one: two years the
# menus offer, earliest first, drawing a column for every year between them
# that had an event.
module EventYearSpan
  # The event did not happen in these two years. They are left off the menus,
  # draw no column, and nothing recorded in them is counted.
  PANDEMIC_YEARS = [2020, 2021].freeze

  # The earliest year a span is offered from.
  FIRST_YEAR = 2010

  ENTRY_YEAR = Arel.sql("YEAR(timesheet.on_duty)")

  # GREATEST, so an entry whose sign-out is before its sign-in counts as no
  # hours rather than as a debit: a few survive from before the app checked,
  # and left signed they cancel out real hours. An entry still open has no
  # sign-out, so its span is NULL, which SUM passes over -- it adds nothing
  # until it is signed out, rather than every hour since it began.
  ENTRY_SECONDS =
    Arel.sql("GREATEST(TIMESTAMPDIFF(SECOND, timesheet.on_duty, timesheet.off_duty), 0)")

  # The years the span's menus offer, newest first.
  def self.year_options = years(FIRST_YEAR, Current.year).reverse

  # Both ends of a span as years the menus offer, earliest first. A span given
  # backwards is turned around rather than refused, so the selects always show
  # the span the report ran over.
  def self.span(start_year, end_year, default_start: Current.year)
    [offered_year(start_year, default_start), offered_year(end_year, Current.year)].minmax
  end

  # The columns a span draws: every year in it that had an event.
  def self.years(start_year, end_year) = (start_year..end_year).to_a - PANDEMIC_YEARS

  # True when a run of event years leaves out a year between its ends -- the
  # run crosses 2020 and 2021. A page asks so it can say why its columns jump.
  def self.skips_years?(years) = years.size < years.last - years.first + 1

  # The last count years that had an event, through the year given, oldest
  # first. Events, not years: five through 2025 are 2019 and 2022 to 2025.
  def self.last_years(count, through:)
    (0..).lazy
         .map { |back| through - back }
         .reject { |year| PANDEMIC_YEARS.include?(year) }
         .first(count)
         .reverse
  end

  # The span in words. One year reads as that year, not as a range from it to
  # itself.
  def self.in_words(start_year, end_year)
    start_year == end_year ? start_year.to_s : "#{start_year} to #{end_year}"
  end

  # Seconds per person per year in the timesheets given, as
  # {person_id => {year => seconds}}, each inner hash answering zero for a year
  # it does not hold.
  #
  # where_years picks the rows and YEAR() sorts them into years; the two agree
  # because they read the same clock. A span crossing 2020 and 2021 takes them
  # into the range, but anything recorded there is a mistake in the data, and
  # is dropped: counted, it would add to a total no column explains.
  def self.seconds_by_person(timesheets, years)
    by_person(timesheets.where_years("timesheet.on_duty", years.first, years.last)
                        .group(:person_id, ENTRY_YEAR)
                        .sum(ENTRY_SECONDS)
                        .select { |(_, year), _| years.include?(year) })
  end

  # {[person_id, year] => n} regrouped as {person_id => {year => n}}, each inner
  # hash answering zero for a year it does not hold.
  def self.by_person(totals)
    totals.each_with_object({}) do |((person_id, year), value), grouped|
      (grouped[person_id] ||= Hash.new(0))[year] += value.to_i
    end
  end

  # A year the menus carry: the one nearest the year asked for, the earlier
  # when it sits between two. So 2009 becomes 2010 and a year past this one
  # becomes this one -- 2009 to 2015 runs 2010 to 2015, not a different span
  # from the one asked for -- and a year with no event becomes the nearest one
  # that had one. A missing or unreadable year becomes the default.
  #
  # The selects rely on this: given a year they do not carry, a select shows
  # its first option instead, and the reader is told the report ran over a span
  # it did not.
  #
  # to_s before to_i: a query string can hand back an array or a nested hash
  # for any parameter, and neither answers to_i.
  def self.offered_year(value, default)
    year = value.to_s.to_i.nonzero? || default

    year_options.min_by { |candidate| [(candidate - year).abs, candidate] }
  end

  private_class_method :offered_year
end
