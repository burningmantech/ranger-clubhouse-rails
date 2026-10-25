# frozen_string_literal: true

# The rangers with the most hours in one year of a span.
#
# Every counted shift between the start and end year is added up per person per
# year, and a ranger is ranked by their single biggest year rather than by the
# span total. Somebody who put in one enormous year therefore outranks somebody
# who spread the same hours across five, which is the question this report is
# asked: who carried a year.
class TopHourEarnersReport
  # How many people the report will list.
  LIMITS = [50, 100, 150, 200, 250].freeze
  DEFAULT_LIMIT = 200

  # The page opens on this many years back, plus the current one.
  DEFAULT_SPAN = 4

  # Who the report ranks. Narrower than Person::ACTIVE_STATUSES on purpose: a
  # retired ranger is off the roster this report is read against, and the page
  # says so in as many words.
  STATUSES = [Person::ACTIVE, Person::INACTIVE].freeze

  # The columns the page reads, plus the two the export adds for a reader
  # allowed to see them. The rest of a person row is long text no one here
  # needs, and a span can turn up thousands of people.
  PERSON_COLUMNS = [:id, :callsign, :status, :preferred_name, :first_name,
                    :last_name, :email].freeze

  # One person's place in the ranking. by_year holds seconds keyed by year and
  # answers zero for a year they did not ranger, so a row always has a value for
  # every column the page draws.
  Row = Data.define(:person, :top_year, :top_duration, :by_year) do
    def callsign = person.callsign

    def status = person.status

    # Only the export asks.
    def name = person.desired_full_name

    def email = person.email

    def duration_for(year) = by_year[year]

    def top_year?(year) = year == top_year

    # Read by the tests alone, to hold the ranking to its promise: the biggest
    # year and the biggest span are different questions.
    def total_duration = by_year.values.sum
  end

  # years lists the columns to draw, and is also the set of years the ranking is
  # decided on, so a row's Top Year is always a column the reader can see.
  #
  # total counts everyone who earned a place before the limit cut the list, so
  # the page can say how many rangers it is not showing.
  Report = Data.define(:start_year, :end_year, :limit, :years, :rows, :total) do
    def any? = rows.any?

    def truncated? = total > rows.size

    # True when the span runs over a year the report leaves out entirely.
    def skips_years? = EventYearSpan.skips_years?(years)
  end

  # Whatever arrived in the query string is turned into a span the report can
  # run before anything is counted, so the page always describes the span it
  # actually used.
  def self.execute(start_year: nil, end_year: nil, limit: nil)
    start_year, end_year = EventYearSpan.span(start_year, end_year,
                                              default_start: Current.year - DEFAULT_SPAN)

    limit = limit.to_s.to_i
    limit = DEFAULT_LIMIT unless LIMITS.include?(limit)

    years = EventYearSpan.years(start_year, end_year)
    ranked = ranked_rows(years)

    Report.new(start_year:, end_year:, limit:, years:,
               rows: ranked.first(limit), total: ranked.size)
  end

  # Everyone who earned a place, in order. The caller cuts the list to the limit
  # and keeps this length, so the page can own up to what it left off.
  #
  # Only people who actually put hours in show up: the ranking is seeded from the
  # timesheets, not from the roster, so a ranger with nothing in the span is
  # absent rather than listed at zero.
  def self.ranked_rows(years)
    by_person = EventYearSpan.seconds_by_person(counted_shifts, years)

    Person.where(id: by_person.keys, status: STATUSES)
          .select(*PERSON_COLUMNS)
          .filter_map { |person| build_row(person, by_person[person.id]) }
          .sort_by { |row| [-row.top_duration, row.callsign.downcase] }
  end

  # Finished shifts on a position that earns hours.
  #
  # A shift no one has signed out of is left out entirely, as the shirt report
  # does with the same sum. Counting one means valuing it up to this moment, and
  # a sign-in left open since January would be credited with every hour since --
  # thousands of them, enough to take first place and stay there.
  def self.counted_shifts
    Timesheet.joins(:position).where(position: { count_hours: true }).with_off_duty
  end

  # A tie on hours goes to the earlier year, so a ranger's best year does not
  # move about between runs.
  def self.build_row(person, by_year)
    return unless by_year.values.sum.positive?

    top_year, top_duration = by_year.max_by { |year, seconds| [seconds, -year] }

    Row.new(person:, top_year:, top_duration:, by_year:)
  end

  # execute is the report; the rest is how it gets there.
  private_class_method :ranked_rows, :counted_shifts
end
