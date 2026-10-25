# frozen_string_literal: true

require "ostruct"

# Every timesheet of an event year, grouped by the person who turned it in.
#
# Ported from Laravel's TimesheetByCallsignReport. Upstream answers the whole
# report in one payload and lets the browser open one accordion at a time; this
# port splits it into a roster (summary) and one person's entries (person), so
# the two entry points below are the same report read at two depths.
#
# Both entry points apply the same visibility scope. Upstream only ever had to
# scope one bulk query -- a partial-report reader who could ask for a single
# person by URL is a hole the drill-down opens and this class closes.
#
# The scope, the status strings, and the credit arithmetic are shared with
# Timesheet by Position; they live in TimesheetYearReport.
class TimesheetByCallsignReport
  include TimesheetYearReport

  class << self
    # The roster: one row per person with that year's entry count and totals.
    def summary(year:, viewer:)
      scope = visible_scope(year:, viewer:)
      return OpenStruct.new(status: TimesheetYearReport::NO_MEMBERSHIP, people: []) unless scope

      rows = scope.includes(:person, :position).to_a
      credits = credits_by_id(rows)

      people = rows.group_by(&:person_id)
                   .map { |person_id, group| build_person(person_id, group, credits) }
                   .sort_by { |row| [PersonRosterRow.natural_callsign_key(row.callsign), row.person_id] }

      OpenStruct.new(status: status_for(viewer), people:)
    end

    # One person's entries for the year, oldest first, with the same totals.
    def person(year:, person_id:, viewer:)
      rows = entries(year:, viewer:, person_id:)
      credits = credits_by_id(rows)

      OpenStruct.new(status: status_for(viewer), entries: rows, credits:,
                     **totals(rows, credits))
    end

    # The raw visible rows, for the CSV exports. Both exports share this so the
    # whole-report file and a person's own file cannot disagree about what the
    # reader was allowed to see.
    def entries(year:, viewer:, person_id: nil)
      scope = visible_scope(year:, viewer:)
      return [] unless scope

      scope = scope.for_person(person_id) if person_id
      scope.includes(:person, :position, :slot).ordered_by_on_duty.to_a
    end

    private

    def build_person(person_id, group, credits)
      person = group.first.person

      OpenStruct.new(person:, person_id:,
                     callsign: PersonRosterRow.callsign(person, person_id),
                     person_status: PersonRosterRow.status(person),
                     **totals(group, credits))
    end

    # count_hours false means the hours are still credited and still count
    # toward tickets -- they just do not buy provisions or appreciations, which
    # is why that total is tracked separately rather than subtracted.
    def totals(rows, credits)
      { entry_count: rows.size,
        total_duration: rows.sum(&:duration),
        total_credits: rows.sum { |row| credits.fetch(row.id, 0.0) },
        total_appreciation_duration: rows.select { |row| row.position&.count_hours }.sum(&:duration) }
    end
  end
end
