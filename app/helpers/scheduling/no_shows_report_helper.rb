# frozen_string_literal: true

module Scheduling::NoShowsReportHelper
  # person_display_link, not callsign_link: Timesheet Management may read these
  # pages but not open person pages, and unguarded links all bounce that reader
  # to /me.
  def no_shows_people(no_shows)
    safe_join(no_shows.map { |row| person_display_link(row.person, row.person_id) }, ", ")
  end

  # Only the exception counts, and nothing at all when a position has none.
  def no_shows_position_badges(position)
    return [] unless position.no_show_count.positive?

    [ui_badge(pluralize(position.no_show_count, "no show"), :error, size: "base")]
  end

  # The flake report answers a narrower version of the same question, so each
  # page points at the other -- but only for a reader who may open it. Edit
  # Slots reads the flake report and not this one; Timesheet Management reads
  # this one and not the flake report, so an unguarded link bounces half the
  # readers of each page to /me.
  #
  # Each gate is read off the controller that enforces it rather than restated
  # here: a role list copied into a helper is a link that keeps promising a
  # page after the page stops admitting the reader.
  def flake_report_readable?
    Current.has_role?(Scheduling::FlakeReportController.authorized_roles)
  end

  def no_shows_report_readable?
    Current.has_role?(Scheduling::NoShowsReportController.authorized_roles)
  end
end
