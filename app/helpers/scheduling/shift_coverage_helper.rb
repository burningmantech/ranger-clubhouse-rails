# frozen_string_literal: true

# Every method here is prefixed. Rails helper names share one namespace across
# the whole app, so a bare `cell` or `period_time` would answer for every other
# page too.
module Scheduling::ShiftCoverageHelper
  # An empty post keeps its dash on the grid, where a column of them is how a
  # gap is spotted, and drops out of the folded card, where the vacant line
  # below says the same thing in one line instead of fifteen.
  #
  # This half of the rule sits next to the other half on purpose: they have to
  # agree about which posts fold away and at what width, and apart they drift
  # into either saying it twice or not at all.
  def shift_coverage_cell_class(cell)
    "hidden lg:table-cell" if cell.vacant?
  end

  # Posts no one is covering, named once under the row's hours -- the other
  # half of the rule above.
  def shift_coverage_vacant_line(period)
    vacant = period.cells.select(&:vacant?).map { |cell| cell.post.title }
    return if vacant.empty?

    # Base size, not small: on a folded card this is the ONLY place a gap is
    # named, so it is the content of the row rather than a note about it.
    # font-normal because it sits inside the row's heading cell, which is bold
    # by default -- the hours are the card's title, not the gaps.
    tag.div("Vacant: #{vacant.join(", ")}",
            class: "lg:hidden mt-1 font-normal text-stone-muted")
  end

  # One column's answer for one row: a headcount, the people on duty, or a dash
  # for a post no one is covering.
  def shift_coverage_cell(cell)
    return cell.count.to_s if cell.count?
    # The same predicate the class above hides the cell by, so the dash and the
    # hiding cannot come apart.
    return tag.span(value_or_dash(nil), class: "text-stone-subtle") if cell.vacant?

    safe_join(cell.groups.each_with_index.map { |group, index|
      shift_coverage_window(cell, group, index)
    })
  end

  # The day filter offers every day the report actually covers, plus all of them.
  def shift_coverage_day_options(report)
    [["All days", ShiftCoverageReport::ALL_DAYS]] + report.day_options
  end

  # A chip only for the day, and only once one is chosen: the shift type is
  # what the report is about rather than something narrowing it, so removing it
  # would have nowhere to land.
  def shift_coverage_filter_chips(report, day, clear_url)
    return [] if day == ShiftCoverageReport::ALL_DAYS

    # The chip carries the day the reader picked it by, not the key the URL
    # spells it with. The day is known to be one of the report's own -- it was
    # checked against them before it got here.
    label = report.days.find { |candidate| candidate.key == day }.label
    filter_chips({ day: label }, { day: "Day" }) { clear_url }
  end

  def shift_coverage_count(report, days)
    shown = days.sum { |day| day.periods.size }
    return "Showing #{pluralize(shown, "period")}" if shown == report.period_count

    "Showing #{shown} of #{pluralize(report.period_count, "period")}"
  end

  private

  # The people sharing a shift window. The hours go unsaid only when there is
  # one window and it covers the whole row -- then the row already states them.
  # Any other case prints them, because a cell that says only "Nobooty" when
  # Nobooty comes on at 17:00 of a 12:00-18:00 row reads as covered when it is
  # not, and a cell holding two windows needs them to tell the two apart.
  def shift_coverage_window(cell, group, index)
    people = safe_join(group.people.map { |person| shift_coverage_person(person) }, ", ")
    return people if cell.groups.one? && group.fills_period

    tag.div(class: index.zero? ? nil : "mt-2") do
      # A wrapped time reads as two times, so the column widens instead.
      safe_join([tag.div(group.span, class: "text-sm text-stone-subtle whitespace-nowrap"), people])
    end
  end

  # Edit Slots reads this page and cannot open person pages, so the callsign
  # falls back to plain text for them.
  #
  # The path is passed rather than left to default: these arrive as callsign
  # rows rather than whole Person records, and only the link's own path needs
  # the id.
  def shift_coverage_person(signup)
    # Built only when it will be used: for a reader who cannot open person
    # pages the link is discarded, and a busy day would compute thousands of
    # paths to throw away.
    path = person_path(signup.person_id) if can_view_person_page?
    name = person_display_link(signup, signup.person_id, path:)
    return tag.span(name, class: "whitespace-nowrap") if signup.tag.blank?

    # Which position the callsign is on is part of the answer, so it stays at
    # the size of the rest of the cell.
    tag.span(class: "whitespace-nowrap") do
      safe_join([name, tag.span("(#{signup.tag})", class: "text-stone-subtle")], " ")
    end
  end
end
