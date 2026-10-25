# frozen_string_literal: true

# Row painting for the mass signout table. The bands come from
# MassSignoutReport; this only decides how each one looks.
#
# Never colour alone: a stale row also carries a warning icon and prints its
# year, and a long row prints its elapsed time in amber next to plain black
# neighbours. The colour is the third signal, not the only one.
module ShiftOperations::MassSignoutHelper
  # How badly each band reads, in the shared vocabulary. :current is absent on
  # purpose -- it maps to nil, which paints nothing, and that is what a plain
  # row wants.
  BAND_SEVERITY = { stale: :error, long: :warning }.freeze

  def mass_signout_row_state(row) = BAND_SEVERITY[row.band]

  # The year is the whole tell on a stale row, and datetime_format hides it by
  # default. datetime_format returns a <span>, so the icon is joined to it
  # rather than interpolated into a string.
  def mass_signout_on_duty_cell(row)
    stamp = datetime_format(row.timesheet.on_duty, year: row.stale?)
    return stamp unless row.stale?

    safe_join([fa_icon("triangle-exclamation", :solid, class: "text-error"), stamp], " ")
  end

  # How long an entry has been open. Past a day a clock reading stops being
  # readable -- "51904:12" tells no one anything -- so it switches to days.
  def mass_signout_elapsed_label(row)
    tag.span(hour_minute_or_day_format(row.elapsed),
             class: severity_style(BAND_SEVERITY[row.band], :text))
  end

  # The checkbox's accessible name. A stale row's danger is carried by a tint
  # and an icon, neither of which a screen reader announces, so the one control
  # on the row says it in words.
  #
  # person_display_name, not person.callsign -- the person row may be gone
  # while the timesheet keeps its id, and the name has to survive that.
  def mass_signout_checkbox_label(row)
    who = person_display_name(row.person, row.person_id)
    return "Select #{who} — this Ranger's record is gone, so this entry cannot " \
           "be signed out" unless row.signable?
    return "Select #{who} — entry left open since a past event, do not sign out" if row.stale?

    "Select #{who}"
  end
end
