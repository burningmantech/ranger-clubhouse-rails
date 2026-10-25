# frozen_string_literal: true

module Timesheets::OnDutyHelper
  # The checkbox's checked value, and what the filter chip round-trips. Lives
  # here rather than on the controller so the view can name it without
  # dragging a controller constant into an autoload cycle.
  ON = "1"

  FILTER_CHIP_LABELS = { duty_date: "As Of", excessive_only: "Showing" }.freeze

  # The warning callout's link into the filtered view: same duty date, flagged
  # Rangers only.
  def on_duty_excessive_only_url(filter_params)
    filter_url(:timesheets_on_duty_path, filter_params.merge(excessive_only: ON))
  end

  def on_duty_filter_chips(filter_params)
    filter_chips(active_filters(filter_params), FILTER_CHIP_LABELS,
                 value_label: method(:on_duty_chip_value)) do |remaining|
      filter_url(:timesheets_on_duty_path, remaining)
    end
  end

  # The duty date echoes back exactly what was typed -- it is what the field
  # holds, and reformatting it would leave the chip and the field disagreeing.
  def on_duty_chip_value(key, value)
    (key == :excessive_only) ? "Out longer than usual" : value
  end

  # The person may be gone: the Laravel-shared schema carries no FKs, so a
  # non-optional belongs_to still reads nil and callsign_link raised on it,
  # taking the whole board down over one orphaned row.
  def on_duty_person_label(entry)
    return callsign_link(entry.person) if entry.person

    person_display_name(nil, entry.timesheet.person_id)
  end

  # The second line under every ranger: where the shift came from, how long it
  # was meant to run, and -- when flagged -- how far past that they are. Every
  # row carries it, so nothing on this page is behind an interaction.
  def on_duty_detail_line(entry, duty_date)
    parts = if entry.slot
              # datetime_format returns a <span>, so it is joined rather than
              # interpolated -- interpolation would hand safe_join a plain
              # String and the markup would be escaped into the page.
              [safe_join(["shift ", datetime_format(entry.slot.begins)]),
               "#{hour_minute_format(entry.normal_duration)} scheduled"]
            else
              # Upstream printed "- no shift associated -". It is real
              # information -- the six-hour assumption comes from here -- so it
              # is said in words rather than as a dash.
              ["no shift attached"]
            end

    # Only meaningful when the page is looking at a past instant: in "right
    # now" mode every row is open by definition.
    parts << on_duty_off_duty_part(entry) if duty_date

    if entry.excessive?
      parts << "#{hour_minute_format(entry.excessive_duration)} over " \
               "(+#{entry.excessive_percentage}%)"
    end

    safe_join(parts, " · ")
  end

  def on_duty_off_duty_part(entry)
    return "still on duty" unless entry.timesheet.off_duty

    safe_join(["off duty ", datetime_format(entry.timesheet.off_duty)])
  end

  # Amber for a flagged ranger, plain for everyone else. The whole row shifts,
  # not just a badge, so a flagged name reads at a glance from across HQ.
  def on_duty_row_classes(entry)
    base = "rounded-base p-2"
    entry.excessive? ? "#{base} bg-warning/10" : base
  end

  def on_duty_elapsed_classes(entry)
    base = "shrink-0 text-lg font-semibold tabular-nums"
    entry.excessive? ? "#{base} text-warning" : "#{base} text-heading"
  end
end
