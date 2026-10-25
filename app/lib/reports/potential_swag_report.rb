# frozen_string_literal: true

# Potential Swag: the service pin and patch order sizer. One row per person in
# an active status -- how many years they have rangered, the first and last of
# them, whether they have signed up for anything this event, and which 5-year
# service milestone the coming event would be for them.
#
# The milestone is the point of the report: years + 1, when that lands on a
# multiple of five. Someone with four years rangered is a 5-year pin candidate
# at the coming event, whether or not they turn up.
#
# Deliberately NOT year-scoped: only #signed_up carries a year, and the caller
# passes it.
#
# The years count comes from person.years_as_ranger, which is what upstream
# counts too (Timesheet::yearsRangeredCountForIds reads the same column), so the
# Years column and the milestones derived from it match upstream exactly.
#
# first_year / last_year are a knowing divergence: upstream runs a second raw
# timesheet query for them that excludes only Alpha and Training, so its Years
# and its First/Last can describe different sets of years on one row. Taking all
# three from years_as_ranger keeps a row self-consistent and agreeing with the
# person's profile. See EventsRangeredReport, which made the same call.
class PotentialSwagReport
  MILESTONE_INTERVAL = 5

  # Plain value rows, not Person records: every active-status account is a few
  # thousand people and nothing on the page needs an association.
  Row = Data.define(:id, :callsign, :status, :years, :first_year, :last_year,
                    :signed_up, :milestone) do
    # Upstream's service_eligible string, and the CSV cell. nil when the coming
    # event is not a milestone.
    def service_label = milestone && "#{milestone}-year service"
  end

  # @param year [Integer] the event year the sign-up column asks about
  # @return [Array<Row>] callsign order, case-insensitively
  def self.execute(year)
    # Upstream writes ->where('status', Person::ACTIVE_STATUSES) -- an array
    # passed where Laravel expects a scalar. Person.active is that call's
    # obvious intent, and is literally that where.
    people = Person.active
                   .pluck(:id, :callsign, :status, :years_as_ranger)
                   .reject { |_id, callsign, _status, _years| callsign.to_s.match?(Person::TEST_CALLSIGN) }
    return [] if people.empty?

    signed_up = signed_up_ids(year)

    people.map { |id, callsign, status, ranger|
      # years_as_ranger is JSON text on a table the upstream Laravel app also
      # writes, and MariaDB's json_valid() admits scalars and objects, so a
      # malformed row is treated as no service rather than left to raise and
      # take the whole report down with it.
      #
      # grep(Integer), not is_a?(Array) alone: json_valid() is just as happy
      # with [null, 2020] or [2019, "2020"], and min/max on a mixed array
      # raises ArgumentError -- which would 500 the page and the CSV for every
      # reader, the exact outcome this guard exists to prevent. Anything that
      # is not a year is dropped rather than compared.
      years = ranger.is_a?(Array) ? ranger.grep(Integer) : []

      # People with no service are kept, unlike EventsRangeredReport: this
      # report is scoped by status rather than by service, and someone at zero
      # years is an active account who will reach a milestone eventually.
      # min/max are nil for them, which the view renders as a dash.
      Row.new(id:, callsign: callsign.to_s, status:, years: years.size,
              first_year: years.min, last_year: years.max,
              signed_up: signed_up.include?(id), milestone: milestone_for(years.size))
    }.sort_by { |row| row.callsign.downcase }
  end

  # The milestone the coming event would be, or nil. Zero years gives 1, which
  # is not a milestone, so a brand new account draws no badge.
  #
  # "The coming event" drifts mid-event: once someone has rangered six hours of
  # the current year, that year joins years_as_ranger and years + 1 starts
  # describing NEXT year, while the page still says Current.year. Upstream
  # behaves the same way, and the report is read before the event, so this is
  # parity rather than a bug worth diverging over.
  #
  # @param years [Integer] years rangered so far
  # @return [Integer, nil]
  def self.milestone_for(years)
    next_total = years + 1
    next_total if (next_total % MILESTONE_INTERVAL).zero?
  end

  # Sign-ups have to be queried live. person.years_of_signups counts every slot
  # including trainings, and this column deliberately excludes training
  # positions -- an Alpha who has only signed up for a Training is not coming to
  # ranger.
  #
  # Written as "the slot's position is not one of the Training positions" rather
  # than upstream's join onto position.type != 'Training'. position.type is
  # nullable, and in SQL a NULL type is not "not Training" -- it is unknown, so
  # the comparison drops the row and the person loses a sign-up they have. No
  # position carries a NULL type today, but nothing stops one from doing so.
  # The subquery is NULL-safe (position_id is NOT NULL, ids are never NULL),
  # counts a sign-up whose position row is missing entirely, and needs one join
  # fewer.
  #
  # Not narrowed to the roster's person ids: the caller only ever asks this set
  # #include?, so scoping it would ship a several-thousand-element IN list to
  # re-derive an intersection Ruby does anyway.
  #
  # @return [Set<Integer>]
  def self.signed_up_ids(year)
    PersonSlot.joins(:slot)
              .where(slot: { begins_year: year })
              .where.not(slot: { position_id: Position.by_type(Position::TYPE_TRAINING)
                                                      .select(:id) })
              .distinct
              .pluck(:person_id)
              .to_set
  end
  private_class_method :signed_up_ids

  # The order sheet: one line per milestone the roster can currently produce,
  # largest first. Built from the same rows the roster draws from, so a line and
  # its people can never disagree.
  #
  # Rows at no milestone are dropped first; the roll-up itself, including the
  # :matching contract, is RosterRollup's -- see it for what each count means.
  #
  # @param rows [Array<Row>]
  # @return [Array<Hash>] { milestone:, people:, signed_up:, matching: }
  def self.milestones(rows, &matching)
    RosterRollup.by(rows.select(&:milestone), :milestone, &matching)
  end
end
