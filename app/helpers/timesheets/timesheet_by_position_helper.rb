# frozen_string_literal: true

module Timesheets::TimesheetByPositionHelper
  # The index row's second line: what the reader is deciding between before
  # spending a click. Hours first -- the counts only say how the hours are
  # split up.
  def timesheet_by_position_meta(row)
    "#{hour_minute_format(row.total_duration)} hrs • " \
      "#{pluralize(row.entry_count, "entry")} • #{pluralize(row.people_count, "ranger")}"
  end

  # Only the exceptions are badged. Most positions on the index are active and
  # count toward provisions, and a chip on every one of 140 rows is 140 chips
  # saying nothing -- the same rule the by-callsign index follows.
  def timesheet_by_position_badges(row)
    badges = []
    unless row.active
      badges << ui_badge("Inactive", :secondary, icon: "circle-pause", icon_type: :solid,
                                                 size: "base")
    end
    unless row.count_hours
      badges << ui_badge("No provisions", :warning, icon: "ban", icon_type: :solid,
                                                    size: "base")
    end
    badges
  end

  def timesheet_by_position_chips(filter_params, year)
    filter_chips(filter_params, { title: "Position", active: "Status" }) do |remaining, _key|
      timesheets_timesheet_by_position_path(year:, **remaining)
    end
  end
end
