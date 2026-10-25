# frozen_string_literal: true

# Every shift sign-up of an event year, grouped by the person who signed up.
#
# Ported from Laravel's ScheduleByCallsignReport. Upstream answers the whole
# year in one payload -- every slot, every position, every sign-up -- and lets
# the browser open one accordion at a time. This port splits it into a roster
# (summary) and one person's shifts (person), so the two entry points below are
# the same report read at two depths.
#
# Two deliberate departures from upstream:
#
# 1. Each person's shifts come back ordered by when they start. Upstream's
#    sign-up query carries no ordering, so its accordion tables render in
#    person_slot row order -- the order someone happened to sign up in, which
#    for a schedule is no order at all.
# 2. A sign-up whose person row is gone drops out, rather than being reported
#    under a placeholder callsign. The join does it: this report is read to
#    plan an event, and a row naming no one cannot be acted on.
class ScheduleByCallsignReport
  # One roster row. first_begins/last_ends bound the person's event, which is
  # what the roster is scanned for -- who is here early, who is here all week.
  #
  # The end is MAX(ends), not MAX(begins). Graveyard shifts are ordinary here: a
  # last shift running 22:00 to 06:00 leaves on the following day, and bounding
  # the event by when its final shift STARTED drops that day. It also collapses
  # a single overnight shift to one date, claiming a one-day presence for
  # someone who was here for two.
  Summary = Struct.new(:person_id, :callsign, :person_status, :shift_count,
                       :total_duration, :first_begins, :last_ends)

  # One person's year. `slots` carry their own position, so the detail view
  # needs nothing else, and the three figures are read off them rather than
  # stored beside them -- a stored total is one more thing that can disagree
  # with the rows it claims to describe.
  Detail = Struct.new(:slots) do
    def shift_count = slots.size
    def total_duration = slots.sum(&:duration)
    def position_count = slots.map(&:position_id).uniq.size
  end

  class << self
    # The roster: one row per person with that year's sign-up count, hours, and
    # date span.
    #
    # Every figure the roster shows is an aggregate, so the database computes
    # them: a year holds around six thousand sign-ups and the page shows around
    # nine hundred rows, and grouping in Ruby would drag the other five thousand
    # across the wire -- each with a datetime to cast -- only to add them up and
    # throw them away.
    #
    # Grouped by all three person columns rather than the id alone, so the query
    # is legal whether or not the server runs with ONLY_FULL_GROUP_BY.
    #
    # in_time_zone on the two dates is load-bearing, not decoration. An
    # ActiveRecord attribute read is cast into Time.zone and hands back the wall
    # clock the row stores; MIN()/MAX() are expressions Rails has no column type
    # for, so they arrive as bare Times in the host's zone instead. The two
    # differ whenever the host is not on Time.zone's offset, which for a shift
    # just past midnight is a whole day -- the roster would name one day and the
    # person page it links to another, for the same shift.
    def summary(year:)
      PersonSlot.joins(:slot, :person)
                .where(slot: { begins_year: year })
                .group("person.id", "person.callsign", "person.status")
                .pluck("person.id", "person.callsign", "person.status",
                       Arel.sql("COUNT(*)"), Arel.sql("SUM(slot.duration)"),
                       Arel.sql("MIN(slot.begins)"), Arel.sql("MAX(slot.ends)"))
                .map { |id, callsign, status, shifts, duration, first_begins, last_ends|
                  # to_i on the sum: SUM() comes back a BigDecimal, and Detail's
                  # total_duration for the same figure is an Integer. One field
                  # name, two types, is a difference that only shows up in
                  # whichever consumer does not route through the hour helpers.
                  Summary.new(id, callsign, status, shifts, duration.to_i,
                              first_begins.in_time_zone, last_ends.in_time_zone)
                }
                # Upstream sorts with strcasecmp -- plain case-insensitive, not
                # the natural sort its timesheet sibling uses. person_id breaks
                # ties so two people sharing a callsign keep a stable order.
                .sort_by { |row| [row.callsign.downcase, row.person_id] }
    end

    # One person's shifts for the year, earliest first.
    #
    # Year-scoped like the roster it is reached from. Without that, a hand-typed
    # URL would report a person's whole history from a page whose every other
    # number describes one year.
    def person(year:, person_id:)
      Detail.new(Slot.includes(:position)
                     .for_year(year)
                     .ordered_by_begins
                     .where(id: PersonSlot.where(person_id:).select(:slot_id))
                     .to_a)
    end
  end
end
