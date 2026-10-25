# frozen_string_literal: true

require "ostruct"

# Every timesheet of an event year, grouped by the position it was turned in
# for.
#
# Ported from Laravel's TimesheetByPositionReport. Upstream answers the whole
# report in one payload and lets the browser open one accordion at a time; this
# port splits it into an index of positions (summary) and one position's entries
# (position), the way its Timesheets by Callsign twin does.
#
# The visibility scope, the status strings, and the credit arithmetic are shared
# with that twin and live in TimesheetYearReport -- the two reports are one
# report grouped two ways and must not answer either question differently.
class TimesheetByPositionReport
  include TimesheetYearReport

  class << self
    # The index: one row per position with that year's totals.
    def summary(year:, viewer:)
      scope = visible_scope(year:, viewer:)
      return OpenStruct.new(status: TimesheetYearReport::NO_MEMBERSHIP, positions: []) unless scope

      rows = scope.includes(:position).to_a
      credits = credits_by_id(rows)

      positions = rows.group_by(&:position_id)
                      .map { |position_id, group| build_position(position_id, group, credits) }
                      .sort_by { |row| [row.title.downcase, row.position_id] }

      OpenStruct.new(status: status_for(viewer), positions:)
    end

    # One position's entries for the year, oldest first, with the same totals.
    #
    # `readable` answers the drill-down's authorization question here rather
    # than leaving the page to ask it: the reader's scope is already looked up
    # to build the query, so asking again would buy the same three rows twice.
    # It is true for a position the reader's own team owns even in a year
    # no one rangered it -- which an empty result could never tell us.
    def position(year:, position_id:, viewer:)
      position_ids = readable_position_ids(viewer)
      scope = scope_for(year, position_ids)
      rows = scope ? load_entries(scope.for_position(position_id)) : []
      credits = credits_by_id(rows)

      OpenStruct.new(status: status_for(viewer),
                     readable: position_ids.nil? || position_ids.include?(position_id),
                     entries: rows, credits:, **totals(rows, credits))
    end

    # The raw visible rows, for the CSV exports. Both exports share this so the
    # whole-report file and one position's file cannot disagree about what the
    # reader was allowed to see.
    def entries(year:, viewer:, position_id: nil)
      scope = visible_scope(year:, viewer:)
      return [] unless scope

      scope = scope.for_position(position_id) if position_id
      load_entries(scope)
    end

    private

    def load_entries(scope)
      scope.includes(:person, :position, :slot).ordered_by_on_duty.to_a
    end

    def build_position(position_id, group, credits)
      position = group.first.position

      OpenStruct.new(position:, position_id:,
                     # Upstream's fallback shape. The position row can be gone
                     # while the timesheets remain -- the Laravel-shared schema
                     # carries no FK -- and the index still has to sort.
                     title: position&.title || "Position ##{position_id}",
                     active: position&.active || false,
                     # count_hours false means the hours are still credited and
                     # still count toward tickets -- they just do not buy
                     # provisions or appreciations. It is a property of the
                     # position, so it is one flag per row here rather than the
                     # separate hours total the by-callsign roster carries.
                     count_hours: position&.count_hours || false,
                     **totals(group, credits))
    end

    def totals(rows, credits)
      { entry_count: rows.size,
        people_count: rows.map(&:person_id).uniq.size,
        total_duration: rows.sum(&:duration),
        total_credits: rows.sum { |row| credits.fetch(row.id, 0.0) } }
    end
  end
end
