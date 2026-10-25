# frozen_string_literal: true

module Timesheets::TimesheetsByCallsignHelper
  # What dropdown_scroll_list reads off each entry.
  ScrollItem = Struct.new(:id, :title)

  # The roster row's second line: what the reader is deciding between before
  # spending a click. Hours first -- the count only says how the hours are
  # split up.
  def timesheets_by_callsign_meta(row)
    "#{hour_minute_format(row.total_duration)} hrs • #{pluralize(row.entry_count, "entry")}"
  end

  def timesheets_by_callsign_badges(row) = person_status_exception_badges(row.person_status)

  # Every row is its own scroll target, so the reader picks a callsign rather
  # than a letter and lands on that person -- what upstream's DropdownScrollList
  # did. Roster order is preserved, so each letter's menu reads in the same
  # order the rows below do.
  def timesheets_by_callsign_scroll_items(people)
    people.map { |row| ScrollItem.new(timesheets_by_callsign_anchor(row), row.callsign) }
  end

  # Prefixed rather than the bare "person-<id>" upstream used: this page also
  # renders inside the application layout, and an id is a page-wide claim.
  def timesheets_by_callsign_anchor(row)
    "roster-person-#{row.person_id}"
  end

  # Read off the controller that enforces it rather than restated here. Today
  # this page and /person/:id/timesheets admit the same three roles, and a
  # hard-coded true is a link that keeps promising the page after one of them
  # narrows its gate. (can_view_person_page? covers the Account and Schedule
  # links, which run on PersonConcern::VIEW_ROLES instead.)
  def person_timesheets_readable?
    Current.has_role?(Person::TimesheetsController.authorized_roles)
  end

  def timesheets_by_callsign_chips(filter_params, year)
    filter_chips(filter_params, { callsign: "Callsign", status: "Status" }) do |remaining, _key|
      timesheets_timesheets_by_callsign_path(year:, **remaining)
    end
  end
end
