# frozen_string_literal: true

require "ostruct"

# Every timesheet of an event year, grouped by the person who turned it in and
# then by the position they turned it in for -- but only for positions marked
# to count hours. A position that does not count hours still shows up on
# Timesheets by Callsign; it never shows up here, which is why this report's
# totals will not match that one's for the same person.
#
# Admin-gated whole-page rather than scoped by team ownership, so this report
# reaches TimesheetCredits directly for the shared credit arithmetic rather
# than including TimesheetYearReport -- that concern also carries the
# team-ownership visibility rule its by-callsign and by-position twins need
# and this report does not.
class TimesheetTotalsReport
  class << self
    # The roster: one row per person with that year's totals and the positions
    # making them up.
    def summary(year:)
      rows = load_rows(year)
      credits = TimesheetCredits.credits_by_id(rows)

      rows.group_by(&:person_id)
          .map { |person_id, group| build_person(person_id, group, credits) }
          .sort_by { |row| [PersonRosterRow.natural_callsign_key(row.callsign), row.person_id] }
    end

    # One person's positions for the year, with the same totals.
    def person(year:, person_id:)
      rows = load_rows(year, person_id:)
      credits = TimesheetCredits.credits_by_id(rows)

      OpenStruct.new(position_summary(rows, credits))
    end

    private

    # Joining rather than filtering in Ruby: only a position that still exists
    # can be count-hours or not, so a timesheet whose position has been deleted
    # is excluded here the same way upstream's whereIn on a plucked id list
    # excludes it.
    #
    # person_id narrows at the database rather than in Ruby, so the person page
    # does not pay for the whole year's rows to show one person's handful --
    # and skips the person preload entirely, since that page already has its
    # Person record from the route.
    def load_rows(year, person_id: nil)
      scope = Timesheet.for_year(year)
                       .joins(:position)
                       .merge(Position.where(count_hours: true))
                       .includes(person_id ? :position : [:person, :position])
      scope = scope.for_person(person_id) if person_id
      scope.to_a
    end

    # The person row can be gone -- the Laravel-shared schema carries no FK --
    # while the timesheet remains, and the roster still has to sort.
    def build_person(person_id, group, credits)
      person = group.first.person

      OpenStruct.new(person_id:,
                     callsign: PersonRosterRow.callsign(person, person_id),
                     person_status: PersonRosterRow.status(person),
                     **position_summary(group, credits))
    end

    # A person's positions plus the totals they add up to. Totals are summed
    # from the positions themselves rather than the raw rows a second time --
    # build_position already did that arithmetic once per position.
    def position_summary(rows, credits)
      positions = rows.group_by(&:position_id)
                      .map { |position_id, entries| build_position(position_id, entries, credits) }
                      # position_id tiebreaker: two positions can share a title
                      # (nothing enforces uniqueness), and without one their
                      # relative order would ride on group_by's row order,
                      # which an unordered query does not guarantee.
                      .sort_by { |row| [row.title.downcase, row.position_id] }

      { positions:, total_duration: positions.sum(&:duration), total_credits: positions.sum(&:credits) }
    end

    def build_position(position_id, entries, credits)
      OpenStruct.new(position_id:, title: entries.first.position.title,
                     duration: entries.sum(&:duration),
                     credits: entries.sum { |row| credits.fetch(row.id, 0.0) })
    end
  end
end
