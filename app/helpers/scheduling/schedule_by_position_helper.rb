# frozen_string_literal: true

# Every method here is prefixed. Rails helper names share one namespace across
# the whole app, so a bare `meta` or `badges` would answer for every other page
# too.
module Scheduling::ScheduleByPositionHelper
  # What dropdown_scroll_list reads off each entry.
  ScrollItem = Struct.new(:id, :title)

  # The slots admin admits Admin and Edit Slots, but not Event Management, who
  # read this report too. Asked of that page rather than copied off it, so the
  # button cannot go on promising a page that stopped admitting the reader.
  def schedule_by_position_can_manage_slots?
    Current.has_role?(Scheduling::SlotsController.authorized_roles)
  end

  # The index row's second line: what the reader decides on before spending a
  # click. How many shifts, how full they are, and when the position is out.
  def schedule_by_position_meta(row)
    tally = row.tally

    "#{pluralize(tally.shift_count, "shift")} • " \
      "#{tally.sign_up_count} of #{tally.seat_count} signed up • " \
      "#{schedule_by_position_span(tally)}"
  end

  # A retired position keeps its shifts and its sign-ups, and reading the
  # schedule is when that matters. Spelled the way Timesheet by Position and the
  # slots admin spell it, rather than upstream's red: a retired position is a
  # fact about the position, not a problem with the shift. Most rows carry none.
  def schedule_by_position_badges(row)
    return [] if row.position_active

    [ui_badge("Inactive", :secondary, size: "base", icon: "circle-pause", icon_type: :solid)]
  end

  # Each row is its own scroll target, so the reader picks a position rather
  # than a letter and lands on it -- what upstream's DropdownScrollList did.
  #
  # No blank-title guard: position.title is NOT NULL and presence-validated. A
  # blank one takes the page down either way -- here, on the first character,
  # or a few lines further on at ui_drill_down_row, which refuses to render
  # without a title. Guarding only this one would buy nothing.
  def schedule_by_position_scroll_items(rows)
    rows.map { |row| ScrollItem.new(schedule_by_position_anchor(row), row.title) }
  end

  # Prefixed rather than a bare "position-<id>": this page renders inside the
  # application layout, and an id is a claim on the whole page.
  def schedule_by_position_anchor(row)
    "position-row-#{row.position_id}"
  end

  # The callsigns on one shift, with any linked shift's sign-ups beneath them.
  #
  # An empty shift says so in red: on a coverage report that is the finding, not
  # a blank cell. Red only while it is a gap somebody could close, though --
  # a switched-off shift has no one on it by design, and its Status badge
  # already says so. Same test the Empty Shifts box uses.
  def schedule_by_position_sign_ups(shift)
    own = if shift.sign_ups.any?
            safe_join(shift.sign_ups.map { |sign_up| schedule_by_position_person(sign_up) }, ", ")
          else
            tag.span("No sign-ups",
                     class: shift.slot.active ? "text-error" : "text-stone-subtle")
          end

    safe_join([own] + shift.linked.map { |link| schedule_by_position_linked(link) })
  end

  # Readers of this page include Edit Slots, who cannot open person pages, so
  # the callsign falls back to plain text for them.
  #
  # The path is passed rather than left to default: these arrive as callsign
  # rows, not whole Person records -- a busy position lists thousands of
  # sign-ups -- and only the link builder's own path needs the id.
  def schedule_by_position_person(sign_up)
    person_display_link(sign_up, sign_up.person_id, path: person_path(sign_up.person_id))
  end

  # A shift attached to this one: the parent it feeds, the sub-shift under it,
  # or a shift running alongside under a partner position. Whoever is on it is
  # named, because the question being asked is who covers this hour.
  def schedule_by_position_linked(link)
    phrase = schedule_by_position_linked_phrase(link)

    # Indent and colour carry the hierarchy, not a smaller size: these callsigns
    # answer "who covers this hour" as much as the row's own do, and the house
    # rule keeps text that load-bearing at the base size.
    tag.div(class: "mt-2 border-s-2 border-line ps-2 text-stone-subtle") do
      if link.people.any?
        # Through the same link builder the row's own callsigns use. They are
        # the same kind of record and the same reader is looking at them, so
        # one being clickable and the other dead text has nothing behind it.
        named = safe_join(link.people.map { |person| schedule_by_position_person(person) }, ", ")
        safe_join([tag.div("#{pluralize(link.people.size, "sign-up")} in the #{phrase}:"),
                   tag.div(named)])
      else
        "No one has signed up for the #{phrase}."
      end
    end
  end

  private

  def schedule_by_position_linked_phrase(link)
    case link.kind
    when :parent then "parent #{link.position_title} shift"
    when :child then "#{link.position_title} sub-shift"
    else "corresponding #{link.position_title} shift"
    end
  end

  # The position's stretch of the event, as two dates. A single day is said
  # once rather than twice.
  def schedule_by_position_span(tally)
    return "no shifts" unless tally.first_begins

    first_begins = tally.first_begins
    last_ends = tally.last_ends || first_begins
    # Compared as dates rather than as the two formatted strings: "%b %-d"
    # carries no year, so a position running from one January into the next
    # would read as a single day.
    return schedule_by_position_day(first_begins) if first_begins.to_date == last_ends.to_date

    # And when the two ends do fall in different years, both of them say which:
    # "Dec 31 – Jan 1" leaves the reader to guess.
    year = first_begins.year != last_ends.year
    "#{schedule_by_position_day(first_begins, year)} – #{schedule_by_position_day(last_ends, year)}"
  end

  # Formatted in Time.zone, not through getlocal. The report already converted
  # these -- a plucked MIN()/MAX() is not type-cast and arrives in the host's
  # zone -- and Time.zone is the clock every rendered surface here reads.
  def schedule_by_position_day(time, year = false)
    time.strftime(year ? "%b %-d, %Y" : "%b %-d")
  end
end
