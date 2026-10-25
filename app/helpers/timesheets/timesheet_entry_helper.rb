# frozen_string_literal: true

# How a timesheet entry's two clocks read on the /timesheets report pages.
#
# Timesheets by Callsign and Timesheet by Position show the same rows grouped
# two ways, so the entry's span and its shift's start are formatted once here
# rather than on either page.
module Timesheets::TimesheetEntryHelper
  # datetime_format returns a <span>, so the pieces are joined rather than
  # interpolated -- interpolation hands safe_join a plain String and the markup
  # is escaped into the page.
  def timesheet_entry_time(entry)
    return datetime_format(entry.on_duty, entry.off_duty) if entry.off_duty

    safe_join([datetime_format(entry.on_duty),
               tag.span("still on duty", class: "italic text-stone-subtle")], " ")
  end

  # tz/tz_abbr, as the sibling slot pages pass: a shift carries its own
  # timezone, and rendering it in the app's zone shows a different clock time
  # than the page the shift was created on, with nothing to say which is meant.
  def timesheet_shift_time(slot)
    datetime_format(slot.begins, tz: slot.timezone, tz_abbr: slot.timezone_abbr)
  end
end
