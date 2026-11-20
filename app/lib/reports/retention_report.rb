# frozen_string_literal: true

# Retention: everyone who rangered at least one of the last five events, so the
# Retention Team can send the post-event survey and see who has been away.
#
# Someone counts as having rangered an event if they hold a timesheet entry in
# it that is not Training or Deep Freeze, and is not an echelon shift. An Alpha
# shift counts: whoever passed is on the roster, and is asked like anyone else.
# That check decides who is listed, and the same entries fill the year strip
# (worked_years), so the strip shows the events that put them in the report.
#
# First Year, Last Year and Total Years come from person.years_as_ranger, which
# YearsManagement (app/lib/years_management.rb) keeps up to date, so they and a
# person's profile cannot disagree.
#
# The two rules are close but not identical. years_as_ranger counts Deep Freeze,
# needs six hours in a year from 2025 on, and credits an Alpha year only from
# 2025 and only to someone who passed mentoring -- so the strip can show a year
# the three columns do not count, and someone listed for an Alpha shift alone
# can have no credited year at all.
class RetentionReport
  # How many events the report looks back over, counting the current one.
  EVENT_SPAN = 5

  # Stands in for a Ranger with no credited year at all. They are still in the
  # report -- the shifts that listed them are counted a little differently from
  # the years on their profile -- so the filter has to be able to name them.
  NO_YEARS = "none"

  # What such a Ranger is called on the page.
  NO_YEARS_LABEL = "No full year"

  # Who is asked to take the survey: everyone still on the roster in some form.
  STATUSES = [Person::ACTIVE, Person::INACTIVE,
              Person::INACTIVE_EXTENSION, Person::RETIRED].freeze

  # Shifts that do not count as having rangered an event.
  EXCLUDED_POSITIONS = [Position::TRAINING, Position::DEEP_FREEZE].freeze

  # One person. Plain values rather than Person records: the report runs to
  # well over a thousand rows and nothing on the page needs an association.
  #
  # years are the years the Clubhouse credits, from any time; worked_years are
  # the events in the window with a shift that counts. shiny_penny is true for
  # someone with an Alpha shift in the window's last event.
  Row = Data.define(:id, :callsign, :first_name, :last_name, :status, :email, :years,
                    :worked_years, :shiny_penny) do
    def name = "#{first_name} #{last_name}".strip

    def first_year = years.min

    def last_year = years.max

    def total_years = years.size

    # The last credited year as a filter value. A Ranger with no credited year
    # is still in the report, so the filter has to be able to name them.
    def last_year_key = last_year&.to_s || NO_YEARS
  end

  # The whole report: the years it covers and everyone in it.
  Report = Data.define(:years, :rows) do
    def start_year = years.first

    def end_year = years.last

    # True when the five events reach back over a year that had none.
    def skips_years? = EventYearSpan.skips_years?(years)

    def status_counts = rows.group_by(&:status).transform_values(&:size)

    # How many Rangers each year was the last one they rangered. Keyed by year,
    # plus nil for anyone with no credited year at all.
    def counts_by_last_year = rows.group_by(&:last_year_key).transform_values(&:size)
  end

  # The last five event years, oldest first.
  #
  # @param end_year [Integer] the year the window ends on
  # @return [Array<Integer>]
  def self.years(end_year) = EventYearSpan.last_years(EVENT_SPAN, through: end_year)

  # @param end_year [Integer] the year the window ends on
  # @return [Report] rows ordered by callsign
  def self.execute(end_year: Current.year)
    span = years(end_year)
    worked = worked_years(span)
    pennies = Timesheet.where(position_id: Position::ALPHA)
                       .where_year("timesheet.on_duty", span.last)
                       .distinct.pluck(:person_id).to_set

    rows = Person.where(status: STATUSES)
                 .where(id: worked.keys)
                 .order(:callsign)
                 .pluck(:id, :callsign, :first_name, :preferred_name, :last_name,
                        :status, :email, :years_as_ranger)
                 .map { |id, callsign, first, preferred, last, status, email, years|
                   Row.new(id:, callsign:, status:, email:,
                           worked_years: worked.fetch(id),
                           shiny_penny: pennies.include?(id),
                           first_name: preferred.presence || first.to_s,
                           last_name: last.to_s,
                           # The column is JSON text on a table the Laravel app
                           # also writes, and the check constraint on it admits
                           # [null, 2020] and [2019, "2020"] as happily as a
                           # list of years. Anything that is not a year is
                           # dropped, so a mixed row cannot quietly land in the
                           # wrong count.
                           years: years.is_a?(Array) ? years.grep(Integer) : [])
                 }

    Report.new(years: span, rows:)
  end

  # The events in the window each person has a shift that counts in, oldest
  # first, as {person_id => [year, ...]}. Its keys are everyone with such a
  # shift, whom the report then narrows by status. One pass over the window
  # rather than a lookup per person, matching how the other person-by-timesheet
  # reports ask.
  #
  # The window is closed at both ends: a shift after it belongs to an event this
  # report is not about, and on a clock set to a past year there are such rows.
  # A window crossing 2020 and 2021 takes them into its range; a shift recorded
  # there still lists its Ranger, as it always has, but belongs to no event and
  # is left out of their years.
  #
  # @param span [Array<Integer>] the event years, oldest first
  # @return [Hash{Integer => Array<Integer>}]
  def self.worked_years(span)
    Timesheet.where.not(position_id: EXCLUDED_POSITIONS)
             .where(is_echelon: false)
             .where_years("timesheet.on_duty", span.first, span.last)
             .distinct.pluck(:person_id, EventYearSpan::ENTRY_YEAR)
             .group_by(&:first)
             .transform_values { |pairs| span & pairs.map(&:last) }
  end

  private_class_method :worked_years
end
