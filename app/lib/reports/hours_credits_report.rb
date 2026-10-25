# frozen_string_literal: true

# One year of hours and credits, one row per ranger.
#
# The season falls into three parts: the build-up before the gates open, the
# event week itself, and the strike afterwards. Every shift is counted against
# the part it happened in, and a shift running over one of the two boundaries is
# split there -- so its hours and credits land in each part it touched rather
# than all in the one it started in.
class HoursCreditsReport
  # Left off the report. These are people who have not rangered yet, are not
  # rangering, or never will. Their hours are not the season's story, and the
  # readers of this page are asking about the roster that carried it.
  EXCLUDED_STATUSES = [Person::ALPHA, Person::AUDITOR, Person::BONKED,
                       Person::PAST_PROSPECTIVE, Person::PROSPECTIVE,
                       Person::UBERBONKED].freeze

  # The columns the page and the export read. The rest of a person row is long
  # text no one here needs, and a busy year turns up well over a thousand people.
  #
  # years_as_ranger is among them so the seasons a ranger has served are read
  # with the rest of their row rather than by asking for the same thousand
  # people a second time.
  PERSON_COLUMNS = [:id, :callsign, :status, :preferred_name, :first_name,
                    :last_name, :email, :years_as_ranger].freeze

  # One ranger's season. Durations are seconds; credits are fractional.
  Row = Data.define(:person,
                    :pre_event_duration, :pre_event_credits,
                    :event_duration, :event_credits,
                    :post_event_duration, :post_event_credits) do
    def person_id = person.id

    def callsign = person.callsign

    def status = person.status

    def name = person.desired_full_name

    def email = person.email

    # How many seasons this ranger has served, counted from the years already
    # computed and kept on their record. Anything but a list of years is read as
    # none rather than measured, which would answer with a nonsense count.
    def years
      seasons = person.years_as_ranger
      seasons.is_a?(Array) ? seasons.size : 0
    end

    # Hours from positions that earn them. Time on a position that earns no
    # hours is left out of this and is shown nowhere on the page, though the
    # credits it earned are still counted below.
    def counted_duration = pre_event_duration + event_duration + post_event_duration

    def total_credits = pre_event_credits + event_credits + post_event_credits
  end

  # A year whose event dates have never been set has no boundaries to split a
  # season at, so the report cannot run and the page says so instead of drawing
  # a table. event_start is nil in exactly that case.
  Report = Data.define(:event_start, :event_end, :rows) do
    def event_dates? = event_start.present?

    def any? = rows.any?

    def total_duration = rows.sum(&:counted_duration)

    def total_credits = rows.sum(&:total_credits)
  end

  def self.execute(year:)
    event_dates = EventDate.find_for_year(year)
    return Report.new(event_start: nil, event_end: nil, rows: []) unless usable?(event_dates)

    Report.new(event_start: event_dates.event_start,
               event_end: event_dates.event_end,
               rows: build_rows(rangers_with_hours(year), year, event_dates))
  end

  # Both ends have to be set, and in that order, before a season can be cut into
  # parts. A half-entered or back-to-front pair would otherwise be counted from,
  # putting tens of thousands of hours into one column and taking them out of
  # another -- a page that looks filled in and is wholly wrong. Saying the dates
  # are not set is the truthful answer.
  def self.usable?(event_dates)
    event_dates.present? &&
      event_dates.event_start.present? &&
      event_dates.event_end.present? &&
      event_dates.event_start <= event_dates.event_end
  end

  # Everyone the report lists: a status it covers, and at least one shift in the
  # year. Seeded from the timesheets rather than from the roster, so a ranger who
  # sat the year out is absent rather than listed at zero.
  def self.rangers_with_hours(year)
    Person.where.not(status: EXCLUDED_STATUSES)
          .where(id: Timesheet.for_year(year).select(:person_id))
          .select(*PERSON_COLUMNS)
          .order(:callsign)
  end

  def self.build_rows(people, year, event_dates)
    person_ids = people.map(&:id)
    return [] if person_ids.empty?

    entries = entries_by_person(person_ids, year)

    # The year's credit rates, read once for the whole report rather than once
    # per ranger, and every open shift valued against one reading of the clock
    # so two rows of the same report cannot disagree about when "now" was.
    year_credits = PositionCredit.year_credits(year)
    now = Current.time.to_i

    # A person is here because they have a shift in the year, so the entries
    # are always there. The guard is for the shift deleted between the two
    # queries: dropping that row beats taking the page down.
    people.filter_map do |person|
      rows = entries[person.id]
      next if rows.blank?

      build_row(person, rows, year, event_dates, year_credits, now)
    end
  end

  def self.entries_by_person(person_ids, year)
    Timesheet.for_year(year)
             .where(person_id: person_ids)
             .preload(:position)
             .group_by(&:person_id)
  end

  # A shift no one has signed out of is valued up to this moment, the same way a
  # ranger's own timesheet page values it.
  def self.build_row(person, entries, year, event_dates, year_credits, now)
    summary = EventSummary.new(event_dates.event_start.to_i, event_dates.event_end.to_i,
                               year, year_credits:)

    entries.each do |entry|
      on_duty = entry.on_duty.to_i
      # A sign-out earlier than its sign-in counts as no time rather than as a
      # debit. A few of those survive from before the app checked, and left as
      # they are they cancel out hours a ranger really put in.
      off_duty = [(entry.off_duty&.to_i || now), on_duty].max

      # A position whose record has since gone leaves nothing to say whether its
      # hours count, so its time is set aside rather than guessed at.
      summary.compute_totals(entry.position_id, on_duty, off_duty,
                             entry.position&.count_hours || false)
    end

    Row.new(person:,
            pre_event_duration: summary.pre_event_duration,
            pre_event_credits: summary.pre_event_credits,
            event_duration: summary.event_duration,
            event_credits: summary.event_credits,
            post_event_duration: summary.post_event_duration,
            post_event_credits: summary.post_event_credits)
  end

  # execute is the report; the rest is how it gets there.
  private_class_method :usable?, :rangers_with_hours, :build_rows,
                       :entries_by_person, :build_row
end
