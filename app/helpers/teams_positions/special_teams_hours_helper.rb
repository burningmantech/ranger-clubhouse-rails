# frozen_string_literal: true

# Every method here is prefixed. Helper names share one namespace across the
# whole app, so a bare `summary` would answer for every other page too.
module TeamsPositions::SpecialTeamsHoursHelper
  # The folded parameters card's second line: enough to know what the report
  # below was asked for without opening it.
  def special_teams_hours_parameter_summary(form)
    chosen = form.position_ids.size
    parts = [EventYearSpan.in_words(*form.span),
             chosen.positive? ? pluralize(chosen, "position") : "No positions chosen yet"]
    parts << "Sign-ups shown" if form.show_signups
    parts << "Holders included" if form.include_holders
    parts.join(" · ")
  end

  # What the table below it holds, in one line: how many people, for which
  # positions, over which years. Every chosen position is named, because the
  # picker that shows them is folded once there are rows, and a printout has only
  # this line to say what it covers. Choosing every position says so instead of
  # listing them all.
  #
  # shown is how many rows the page draws, which the row limit can hold below
  # the report's own count.
  def special_teams_hours_summary(report, shown:, position_count:)
    total = report.rows.size
    people = pluralize(number_with_delimiter(total), "person")
    people = "#{number_with_delimiter(shown)} of #{people}" if shown < total
    chosen = if report.positions.size == position_count
               "all #{position_count} positions"
             else
               report.positions.map(&:title).to_sentence
             end

    "Showing #{people} for #{chosen}, #{EventYearSpan.in_words(report.start_year, report.end_year)}"
  end

  # What puts a person on the report, in words. Spelled once so the About card
  # and the empty page describe the same report the same way. "Signed in to"
  # rather than "has hours": a shift still in progress lists its person at 0.00.
  def special_teams_hours_counted(report)
    report.show_signups ? "signed in to or signed up for" : "signed in to"
  end

  # Read from the rule the query uses, so the copy cannot drift from it.
  def special_teams_hours_never_listed
    "#{Person::LOCKED_STATUSES.to_sentence.upcase_first} accounts are never listed."
  end

  # Says what was looked for, so an empty page is not read as "nobody holds or
  # signed up for these" when that was never asked -- and which accounts the
  # report leaves out, since those may be the only ones there are.
  def special_teams_hours_empty_message(report)
    during = if report.start_year == report.end_year
               "in #{report.start_year}"
             else
               "from #{report.start_year} to #{report.end_year}"
             end
    holders = ", and no one holds them" if report.include_holders

    "No one #{special_teams_hours_counted(report)} the chosen positions #{during}#{holders}. " \
      "#{special_teams_hours_never_listed}"
  end
end
