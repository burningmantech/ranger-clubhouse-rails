# frozen_string_literal: true

# A person-keyed timesheet roster row: the natural-order sort key readers
# expect callsigns in, and the display-safe fallback for a person whose row is
# gone -- the Laravel-shared schema carries no FK, so a timesheet can outlive
# the person who turned it in.
#
# Shared by Timesheets by Callsign and Timesheet Totals, the two reports that
# group a year by person. Timesheet by Position groups by position instead and
# has its own, unrelated "position row is gone" fallback.
module PersonRosterRow
  class << self
    # Upstream sorts callsigns with PHP's SORT_NATURAL | SORT_FLAG_CASE, so
    # digit runs compare as numbers: 2Step sorts before 10Step, and "Person #9"
    # before "Person #10". Digit runs sort ahead of letters, which is what puts
    # the numeric callsigns in the A-Z strip's leading "#" bucket.
    #
    # Each chunk becomes a same-shaped [kind, number, text] triple so the
    # comparison never puts an Integer against a String.
    def natural_callsign_key(callsign)
      callsign.scan(/\d+|\D+/).map do |chunk|
        chunk.match?(/\A\d/) ? [0, chunk.to_i, ""] : [1, 0, chunk.downcase]
      end
    end

    def callsign(person, person_id) = person&.callsign || "Person ##{person_id}"

    def status(person) = person&.status || "deleted"
  end
end
