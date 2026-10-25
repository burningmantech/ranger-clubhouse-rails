# frozen_string_literal: true

# Retention: everyone who rangered at least one of the last five events, so the
# Retention Team can send the post-event survey and see who has been away.
#
# Someone counts as having rangered an event if they hold a timesheet entry in
# it that is not Alpha, Training, or Deep Freeze, and is not an echelon shift.
# That check decides who is listed; the year columns then come from
# person.years_as_ranger, which YearsManagement (app/lib/years_management.rb)
# keeps up to date, so this page and a person's profile cannot disagree.
#
# The two rules are close but not identical. years_as_ranger counts Deep Freeze,
# needs six hours in a year from 2025 on, and from 2025 credits an Alpha year to
# someone who passed mentoring -- so a Ranger can be listed with a shorter year
# list than the check that listed them, and a first-year Ranger whose only shift
# was the Alpha they passed is credited that year here but is not listed at all.
# The columns say which years the Clubhouse credits, which is the question the
# Retention Team asks; who is listed follows the upstream report.
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
  EXCLUDED_POSITIONS = [Position::ALPHA, Position::TRAINING,
                        Position::DEEP_FREEZE].freeze

  # One person. Plain values rather than Person records: the report runs to
  # well over a thousand rows and nothing on the page needs an association.
  Row = Data.define(:id, :callsign, :first_name, :last_name, :status, :email, :years) do
    def name = "#{first_name} #{last_name}".strip

    def first_year = years.min

    def last_year = years.max

    def total_years = years.size

    def rangered?(year) = years.include?(year)

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

    rows = Person.where(status: STATUSES)
                 .where(id: rangered_in(span))
                 .order(:callsign)
                 .pluck(:id, :callsign, :first_name, :preferred_name, :last_name,
                        :status, :email, :years_as_ranger)
                 .map { |id, callsign, first, preferred, last, status, email, years|
                   Row.new(id:, callsign:, status:, email:,
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

  # Everyone holding a shift that counts as rangering one of the events in the
  # window. One pass over the window rather than a lookup per person, matching
  # how the other person-by-timesheet reports ask.
  #
  # The window is closed at both ends: a shift after it belongs to an event this
  # report is not about, and on a clock set to a past year there are such rows.
  #
  # @param span [Array<Integer>] the event years, oldest first
  # @return [ActiveRecord::Relation]
  def self.rangered_in(span)
    Timesheet.where.not(position_id: EXCLUDED_POSITIONS)
             .where(is_echelon: false)
             .where_years("timesheet.on_duty", span.first, span.last)
             .select(:person_id)
  end

  private_class_method :rangered_in
end
