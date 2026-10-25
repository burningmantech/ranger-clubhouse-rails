# frozen_string_literal: true

# Who is scheduled at each post, period by period, for one kind of shift.
#
# A period is one shift of the type's base position with its start and end
# rounded to the nearest hour, so shifts that begin at ragged times still line
# up into tidy rows. A post is a column: one or more positions read together,
# shown either as the callsigns on duty or as a plain headcount.
#
# The kinds of shift and their posts are rows rather than code: a
# ShiftCoverageGroup is one kind, and its ShiftCoveragePositions are the posts.
class ShiftCoverageReport
  # Shift times round to the nearest hour: add half an hour, then drop the
  # minutes.
  HOUR_ROUNDING = 30.minutes

  # The "show every day" choice, shared with the filter bar so there is one
  # spelling of it.
  ALL_DAYS = UiComponents::FilterBarHelper::ALL_FILTER

  # One column.
  #
  # tags names a short label to print after a callsign, keyed by the position
  # the shift was under. It is how one column carries a position and its junior
  # version without hiding which is which.
  Post = Struct.new(:position_ids, :title, :count_only, :tags)

  # One kind of shift the report can be run for. base_position_ids are the
  # positions whose shifts set the rows.
  Type = Struct.new(:slug, :label, :base_position_ids, :posts)

  # A shift in scope for a column, carrying both its real times and the
  # rounded ones the rows are matched on.
  Shift = Struct.new(:id, :position_id, :begins, :ends, :period_begins, :period_ends)

  # One person on one shift.
  Signup = Struct.new(:person_id, :callsign, :tag)

  # The people who start at the same time within a column's cell.
  #
  # fills_period says the shift covers its whole row and then some. When it
  # does not, the hours have to be printed beside the callsigns: somebody on
  # for two hours of a six-hour row is not the same answer as somebody on for
  # all six, and a bare callsign reads as the second.
  Group = Struct.new(:begins, :ends, :people, :fills_period) do
    def span = ShiftCoverageReport.span_text(begins, ends)
  end

  # One column's answer for one period: either a headcount or the people.
  Cell = Struct.new(:post, :count, :groups) do
    def count? = post.count_only

    # A column that lists people and has none. A headcount is never vacant --
    # it prints its number, and zero says the same thing out loud.
    def vacant? = !count? && groups.empty?
  end

  Period = Struct.new(:begins, :ends, :cells) do
    def span = ShiftCoverageReport.span_text(begins, ends)
  end

  Day = Struct.new(:key, :label, :periods)

  Result = Struct.new(:columns, :days) do
    def any? = days.any?

    def period_count = days.sum { |day| day.periods.size }

    # What the day filter offers, in the order the days run.
    def day_options = days.map { |day| [day.label, day.key] }

    # The days a filter is allowed to name.
    def day_keys = days.map(&:key)

    def filtered_days(key)
      return days if key == ALL_DAYS

      days.select { |day| day.key == key }
    end
  end

  # The shift type the report opens on when none is asked for. See type_for.
  DEFAULT_TYPE = "command"

  class << self
    # The shift type a request names, out of groups: every shift type, in menu
    # order, read once per request so the menu and the report agree. A shift
    # type the report does not have -- a stale bookmark, or a typo -- falls
    # back to the default rather than failing, and when the default itself has
    # been deleted, to the first one in the menu. nil only when none are set up.
    def type_for(slug, groups)
      group = groups.find { |candidate| candidate.slug == slug } ||
              groups.find { |candidate| candidate.slug == DEFAULT_TYPE } ||
              groups.first
      return unless group

      posts = group.shift_coverage_positions.map do |row|
        Post.new(row.position_id_list, row.title, row.count_only, row.labels_by_position)
      end
      Type.new(group.slug, group.title, group.base_position_ids, posts)
    end

    # A stretch of time as text.
    #
    # Formatted in the app's own zone, which is the zone these were read in --
    # not steered into a named one the way the shared datetime helper does. A
    # shift time is the clock on the wall where the shift happens, and moving
    # it would rename the hour the reader is being asked about.
    #
    # The date comes back only when the end lands on another day, which the
    # round-the-clock shifts do -- without it a shift running 09:30 to 09:30
    # reads as lasting no time at all.
    def span_text(begins, ends)
      return "#{begins.strftime("%H:%M")} – #{ends.strftime("%H:%M")}" if begins.to_date == ends.to_date

      "#{begins.strftime("%H:%M")} – #{ends.strftime("%b %-d %H:%M")}"
    end

    # The whole year for one shift type: every period, and who is at each post.
    # coverage is what type_for answered. nil -- no shift type set up at all --
    # and a shift type with no posts yet both read as an empty report: a grid
    # of periods with no columns answers nothing.
    def execute(year:, coverage:)
      return Result.new([], []) if coverage.nil? || coverage.posts.empty?

      bounds = period_bounds(year, coverage.base_position_ids)
      return Result.new(coverage.posts, []) if bounds.empty?

      scope = shift_scope(year, coverage.posts, bounds.first.first, bounds.map(&:last).max)
      by_position = shifts_from(scope).group_by(&:position_id)
      people = people_by_shift(scope)

      periods = bounds.map do |begins, ends|
        Period.new(begins, ends, cells_for(coverage.posts, by_position, people, begins, ends))
      end

      Result.new(coverage.posts, days_for(periods))
    end

    # The report as a spreadsheet, every day of it. The day filter is a way of
    # reading the page, not a different report, so the file always holds the
    # whole year.
    def csv_rows(result)
      rows = [["Period Start", "Period End"] + result.columns.map(&:title)]

      result.days.each do |day|
        day.periods.each do |period|
          rows << [stamp(period.begins), stamp(period.ends)] +
                  period.cells.map { |cell| csv_cell(cell) }
        end
      end

      rows
    end

    private

    # Shift times go out as they are read, for the reason spelled on span_text.
    def stamp(time) = time.strftime(DateTimeHelper::CSV_TIME)

    # The same rule the page follows, so a cell reads the same in both: the
    # hours are left out only for a lone window covering the whole row.
    def csv_cell(cell)
      return cell.count if cell.count?

      lines = []
      cell.groups.each do |group|
        lines << group.span unless cell.groups.one? && group.fills_period
        group.people.each { |person| lines << signup_text(person) }
      end

      lines.join("\n")
    end

    def signup_text(person)
      person.tag.present? ? "#{person.callsign} (#{person.tag})" : person.callsign
    end

    # The rows: one per shift of the base position, rounded to the hour.
    #
    # Two base shifts running at the same time would draw the same row twice,
    # holding the same answer both times, so identical rows collapse into one.
    def period_bounds(year, base_position_ids)
      Slot.for_year(year)
          .for_position(base_position_ids)
          .ordered_by_begins
          .pluck(:begins, :ends)
          .map { |begins, ends| [round_to_hour(begins), round_to_hour(ends)] }
          .uniq
    end

    # Every shift that could land in any row, read once for the whole report
    # rather than once per column.
    #
    # The window is the whole report and then an hour's grace at each end. This
    # only has to be sure of catching everything -- the row-by-row test below
    # decides what actually belongs -- and rounding can pull a shift that ends
    # just before the report starts onto the first row, so the grace is what
    # keeps this a superset of what that test can match.
    def shift_scope(year, posts, window_begins, window_ends)
      Slot.for_year(year)
          .for_position(posts.flat_map(&:position_ids).uniq)
          .where(begins: ..(window_ends + HOUR_ROUNDING), ends: (window_begins - HOUR_ROUNDING)..)
    end

    # Unordered: the rows pick their own shifts, and the order people appear in
    # a cell is settled by groups_for.
    def shifts_from(scope)
      scope.pluck(:id, :position_id, :begins, :ends)
           .map { |id, position_id, begins, ends|
             Shift.new(id, position_id, begins, ends, round_to_hour(begins), round_to_hour(ends))
           }
    end

    # Everyone signed up for these shifts, by shift. Only the two columns the
    # page prints -- a busy count column covers thousands of sign-ups.
    #
    # The shifts are named to the database as the same query that found them,
    # rather than as a list of the ids it came back with: a whole event's worth
    # of shifts makes that list a thousand numbers long.
    def people_by_shift(scope)
      Person.joins(:person_slot)
            .where(person_slot: { slot_id: scope.select(:id) })
            .pluck("person_slot.slot_id", "person.id", "person.callsign")
            .group_by(&:first)
            .transform_values { |rows| rows.map { |_id, person_id, callsign| [person_id, callsign] } }
    end

    def cells_for(posts, by_position, people, begins, ends)
      posts.map do |post|
        shifts = post.position_ids.flat_map { |id| by_position[id] || [] }
                     .select { |shift| overlaps?(shift, begins, ends) }

        if post.count_only
          Cell.new(post, shifts.sum { |shift| people.fetch(shift.id, []).size }, [])
        else
          Cell.new(post, 0, groups_for(post, shifts, people, begins, ends))
        end
      end
    end

    # People sharing a shift window are read as one entry, so a cell says
    # "these people, from here to here" rather than repeating the hours.
    #
    # Grouped on the whole window rather than on its start alone. One column
    # can cover several positions -- a driver and their mentee, an operator and
    # a smooth operator -- and two that start together but end apart would
    # otherwise be printed under a single end time, putting whoever finished
    # first on duty for hours after they went home.
    def groups_for(post, shifts, people, period_begins, period_ends)
      shifts.group_by { |shift| [shift.begins, shift.ends] }
            .sort_by(&:first)
            .filter_map do |(begins, ends), together|
              signups = together.flat_map do |shift|
                people.fetch(shift.id, []).map { |person_id, callsign|
                  Signup.new(person_id, callsign, post.tags[shift.position_id])
                }
              end

              next if signups.empty?

              # Every shift in the group shares a window, so any of them
              # answers for the whole group.
              window = together.first
              fills = window.period_begins <= period_begins && window.period_ends >= period_ends

              Group.new(begins, ends,
                        signups.sort_by { |signup| signup.callsign.to_s.downcase }, fills)
            end
    end

    # Does a shift reach into a row? Compared on the rounded times, so a shift
    # and a row that were written to line up still do after rounding.
    #
    # Anything shorter than the rounding -- a brief shift, or a brief row --
    # lands on a single instant, and an instant counts for whatever it touches.
    # That is the only reading that does not drop it from the report
    # altogether, which is why the degenerate case is not simply excluded.
    def overlaps?(shift, begins, ends)
      if shift.period_begins == shift.period_ends || begins == ends
        return shift.period_begins <= ends && shift.period_ends >= begins
      end

      shift.period_begins < ends && shift.period_ends > begins
    end

    # Labelled the way the other schedule day filters label a day, so the same
    # day reads the same wherever it is offered.
    def days_for(periods)
      periods.group_by { |period| period.begins.strftime("%m%d") }
             .map { |key, group| Day.new(key, group.first.begins.strftime(DateTimeHelper::DAY_LABEL), group) }
    end

    def round_to_hour(time) = (time + HOUR_ROUNDING).beginning_of_hour
  end
end
