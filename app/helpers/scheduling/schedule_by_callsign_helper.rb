# frozen_string_literal: true

# Every method here is prefixed: Rails helper names share one global namespace
# across the whole app, so a bare `meta` or `badges` would answer for every
# other page too.
module Scheduling::ScheduleByCallsignHelper
  # What dropdown_scroll_list reads off each entry.
  ScrollItem = Struct.new(:id, :title)

  # The roster row's second line: what the reader is deciding between before
  # spending a click. Shifts first -- this is a schedule, and the count is the
  # commitment; the hours say how big each one is.
  def schedule_by_callsign_meta(row)
    "#{pluralize(row.shift_count, "shift")} • #{hour_minute_format(row.total_duration)} hrs " \
      "• #{schedule_by_callsign_span(row)}"
  end

  # Only the exception is badged, and it is coloured by the app-wide status
  # vocabulary -- see Person::StatusesHelper.
  def schedule_by_callsign_badges(row) = person_status_exception_badges(row.person_status)

  # Every row is its own scroll target, so the reader picks a callsign rather
  # than a letter and lands on that person -- what upstream's DropdownScrollList
  # did. Roster order is preserved, so each letter's menu reads in the same
  # order the rows below do.
  #
  # A blank callsign is dropped rather than listed: dropdown_scroll_list buckets
  # on `title[0].upcase`, and on "" that is nil.upcase -- a 500 for the whole
  # roster. The column is NOT NULL but not non-empty, and Laravel writes this
  # table too. The person keeps their row; they just cannot be jumped to.
  def schedule_by_callsign_scroll_items(people)
    people.reject { |row| row.callsign.blank? }
          .map { |row| ScrollItem.new(schedule_by_callsign_anchor(row), row.callsign) }
  end

  # Prefixed rather than the bare "person-<id>" upstream used: this page renders
  # inside the application layout, and an id is a page-wide claim.
  def schedule_by_callsign_anchor(row)
    "roster-person-#{row.person_id}"
  end

  # A position can be retired while its slots keep their sign-ups, and reading
  # the schedule is when that matters -- upstream flags it the same way.
  #
  # Upstream's flag is red; this one is not. Two pages already badge this exact
  # fact -- Timesheet by Position and the slots admin -- and both spell it
  # :secondary with circle-pause. A retired position is a fact about the
  # position, not a problem with the sign-up, and matching the app the reader
  # already knows beats matching the Bootstrap page being replaced.
  def schedule_by_callsign_position(position)
    return "—" unless position
    return position.title if position.active

    safe_join([position.title,
               ui_badge("Inactive", :secondary, size: "base",
                        icon: "circle-pause", icon_type: :solid)], " ")
  end

  def schedule_by_callsign_chips(filter_params, year)
    labels = { callsign: "Callsign", status: "Status" }

    filter_chips(filter_params, labels) do |remaining, _key|
      scheduling_schedule_by_callsign_path(year:, **remaining)
    end
  end

  private

  # The person's event, as two dates. A single-day span says one date rather
  # than the same one twice. Private: only the meta line above calls it, and a
  # helper module is a page-wide namespace, so nothing goes in it unasked.
  def schedule_by_callsign_span(row)
    first = schedule_by_callsign_day(row.first_begins)
    last = schedule_by_callsign_day(row.last_ends)

    first == last ? first : "#{first} – #{last}"
  end

  # Formatted in Time.zone, NOT through getlocal.
  #
  # The value arrives already converted -- the report calls in_time_zone on it,
  # because a plucked MIN()/MAX() is not type-cast and would otherwise be in the
  # host's zone. Time.zone is the clock every rendered surface in this app reads
  # (datetime_format re-stamps these same digits), and getlocal would put this
  # one line an hour off the person page it links to, or a day off across
  # midnight. The CSV builders format the same values the same way, for the same
  # reason.
  def schedule_by_callsign_day(time)
    time.strftime("%b %-d")
  end
end
