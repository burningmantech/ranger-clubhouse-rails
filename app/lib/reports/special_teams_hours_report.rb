# frozen_string_literal: true

# Hours per year in the positions a reader picks -- the Rangers' special teams,
# though any position can be chosen -- and, when asked for, how many shifts
# each person signed up for on them.
#
# One row per person. Their hours on every chosen position are added together,
# so someone who moved between two of them in a year reads as one line with the
# year's whole total.
#
# A person is listed for signing in to a chosen position in the span -- a shift
# still in progress lists them at no hours -- for signing up for one that has
# ended when sign-ups are asked for, and for holding one when holders are asked
# for. Accounts in Person::LOCKED_STATUSES are never listed.
class SpecialTeamsHoursReport
  # The columns the page and the export read. The rest of a person row is long
  # text no one here needs, and a wide span can list thousands of people.
  PERSON_COLUMNS = [:id, :callsign, :status, :preferred_name, :first_name,
                    :last_name, :email].freeze

  # A person with nothing in either count. Frozen, and shared: a read of a
  # missing year answers zero without writing anything into it.
  NONE = Hash.new(0).freeze

  # One person's line. Both hashes are keyed by year and answer zero for a year
  # with nothing in it, so a row has a value for every column the page draws.
  Row = Data.define(:person, :hours_by_year, :signups_by_year) do
    def callsign = person.callsign

    def status = person.status

    def name = person.desired_full_name

    def email = person.email

    def hours_for(year) = hours_by_year[year]

    def signups_for(year) = signups_by_year[year]

    def total_hours = hours_by_year.values.sum

    def total_signups = signups_by_year.values.sum
  end

  # years lists the columns to draw: the span, less the years with no event.
  Report = Data.define(:start_year, :end_year, :years, :positions, :rows,
                       :include_holders, :show_signups) do
    def any? = rows.any?

    # True when the span runs over a year the report leaves out entirely.
    def skips_years? = EventYearSpan.skips_years?(years)

    def hours_total(year) = rows.sum { |row| row.hours_for(year) }

    def signups_total(year) = rows.sum { |row| row.signups_for(year) }

    def total_hours = rows.sum(&:total_hours)

    def total_signups = rows.sum(&:total_signups)
  end

  # The span is turned into one the menus offer before anything is counted, so
  # the report always describes the span it actually used.
  def self.execute(position_ids:, start_year:, end_year:, include_holders: false, show_signups: false)
    start_year, end_year = EventYearSpan.span(start_year, end_year)
    years = EventYearSpan.years(start_year, end_year)
    positions = Position.where(id: position_ids).select(:id, :title).order(:title).to_a
    ids = positions.map(&:id)

    hours = EventYearSpan.seconds_by_person(Timesheet.for_position(ids), years)
    signups = show_signups ? EventYearSpan.by_person(signups_by_person_year(ids, years)) : {}

    person_ids = hours.keys | signups.keys
    person_ids |= PersonPosition.where(position_id: ids).distinct.pluck(:person_id) if include_holders

    rows = Person.where(id: person_ids).where.not(status: Person::LOCKED_STATUSES)
                 .select(*PERSON_COLUMNS).order(:callsign)
                 .map do |person|
      Row.new(person:, hours_by_year: hours.fetch(person.id, NONE),
              signups_by_year: signups.fetch(person.id, NONE))
    end

    Report.new(start_year:, end_year:, years:, positions:, rows:, include_holders:, show_signups:)
  end

  # Sign-ups per person per year on the chosen positions, as
  # {[person_id, year] => count}. A shift belongs to the year it begins in, which
  # the slot carries in a column of its own.
  #
  # Only shifts that have ended count. The column sits beside hours, which a
  # shift adds only once it is signed out, so a sign-up for a shift still to come
  # -- most of the year's sign-ups, run in July -- would read as a no-show. A
  # shift since deactivated still counts: the person signed up for it all the
  # same.
  def self.signups_by_person_year(ids, years)
    PersonSlot.joins(:slot)
              .merge(Slot.for_position(ids).for_year(years).where(ends: ..Current.time))
              .group(:person_id, "slot.begins_year")
              .count
  end

  # execute is the report; the rest is how it gets there.
  private_class_method :signups_by_person_year
end
