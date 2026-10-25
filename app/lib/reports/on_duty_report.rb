# frozen_string_literal: true

# Who is on duty -- right now, or at one instant in the past.
# (Upstream Laravel app/Lib/Reports/OnDutyReport.php.)
#
# An entry is flagged when its elapsed time runs past 1.5x the length of the
# shift it signed into, or past 1.5x six hours when no shift is attached.
# excessive_only narrows the board to just those, which drops whole positions.
class OnDutyReport
  # What a shift is assumed to run when the timesheet has no slot attached.
  DEFAULT_SHIFT_DURATION = 6.hours.to_i

  EXCESSIVE_FACTOR = 1.5

  # How far before the asked-about instant a shift may have started and still
  # count. This replaces a calendar-year scope, which had two faults: its bounds
  # were built in the machine zone while the instant was built in Time.zone, so
  # the two could contradict each other outright; and it cut at midnight on Jan
  # 1, dropping the still-open shift that began the evening before -- the exact
  # row the open-entry window exists to surface. Longer than any event, so
  # no one real is hidden, and short enough that a never-closed entry from a
  # past year stays off the board.
  MAX_SHIFT_LOOKBACK = 14.days

  Entry = Data.define(:timesheet, :elapsed, :normal_duration, :excessive_duration,
                      :excessive_percentage) do
    def excessive? = !excessive_duration.nil?
    def person = timesheet.person
    def slot = timesheet.slot
  end

  PositionGroup = Data.define(:id, :title, :entries) do
    def excessive_count = entries.count(&:excessive?)
  end

  Result = Data.define(:positions, :as_of, :duty_date, :total_people, :excessive_count,
                       :no_shift_count) do
    def empty? = positions.empty?
    def entries = positions.flat_map(&:entries)
    def excessive_entries = entries.select(&:excessive?)
  end

  class << self
    # duty_date nil asks who is on duty right now; a time asks who was on duty
    # at that instant.
    def execute(duty_date: nil, excessive_only: false)
      as_of = duty_date || Current.time

      entries = timesheets(duty_date).filter_map do |timesheet|
        entry = build_entry(timesheet, as_of)
        entry if entry.excessive? || !excessive_only
      end

      Result.new(positions: group_by_position(entries),
                 as_of:,
                 duty_date:,
                 total_people: entries.size,
                 excessive_count: entries.count(&:excessive?),
                 no_shift_count: entries.count { |entry| entry.slot.nil? })
    end

    private

    def timesheets(duty_date)
      scope = Timesheet.includes(:person, :position, :slot).order(:on_duty)

      # Both branches bound how far back on_duty may reach. Without it the
      # "right now" board carries every never-closed entry ever written: a
      # forgotten 2019 sign-in renders tens of thousands of hours, flags itself
      # excessive, sorts its position to the top and lands in the callout,
      # burying whoever is actually still out.
      unless duty_date
        return scope.on_duty_now.where(on_duty: (Current.time - MAX_SHIFT_LOOKBACK)..)
      end

      # Upstream's window is `off_duty >= T`, which never matches NULL and so
      # dropped anyone still out -- exactly the row this page exists to find.
      # The port includes them. Both bounds are built from duty_date, so they
      # are in one zone and cannot disagree.
      window = scope.where(on_duty: (duty_date - MAX_SHIFT_LOOKBACK)..duty_date)
      window.where(off_duty: duty_date..).or(window.where(off_duty: nil))
    end

    def build_entry(timesheet, as_of)
      # Elapsed is always measured to as_of, never past it. Timesheet#duration
      # measures to *now*, which is wrong for a past instant; but so is a closed
      # entry's own off_duty when that falls after as_of -- the point-in-time
      # window selects exactly those rows, and counting the whole shift would
      # flag someone for hours they had not yet been on duty at the instant
      # asked about. Floored at zero so a sign-on stamped ahead of as_of (a
      # mistyped correction, a frozen clock) cannot produce a negative that
      # hour_minute_format renders as a garbled clock.
      finish = [timesheet.off_duty || as_of, as_of].min
      elapsed = [(finish - timesheet.on_duty).to_i, 0].max

      # A slot with a zero duration divides by zero upstream. Treat it as
      # unscheduled rather than crashing the page.
      normal = timesheet.slot&.duration.to_i
      normal = DEFAULT_SHIFT_DURATION unless normal.positive?

      unless elapsed > normal * EXCESSIVE_FACTOR
        return Entry.new(timesheet:, elapsed:, normal_duration: normal,
                         excessive_duration: nil, excessive_percentage: nil)
      end

      Entry.new(timesheet:, elapsed:, normal_duration: normal,
                excessive_duration: elapsed - normal,
                # Truncated, not rounded, as upstream's (int) cast is. The
                # number is advisory.
                excessive_percentage: (elapsed / normal.to_f * 100.0 - 100).to_i)
    end

    # Positions holding a flagged entry sort first -- they are why the page is
    # open. Upstream sorts by title alone, which is kept as the tiebreak.
    def group_by_position(entries)
      # Grouped by position_id, not by the association: the Laravel-shared
      # schema carries no FKs, so a position deleted after the timesheet was
      # written leaves a non-optional belongs_to reading nil, and one such row
      # took the whole page down. The placeholder title is the same one
      # Position.retrieve_title and SurveyBuilder already use.
      entries.group_by { |entry| entry.timesheet.position_id }
             .map { |position_id, group|
               title = group.first.timesheet.position&.title || "Position ##{position_id}"
               PositionGroup.new(id: position_id, title:, entries: group)
             }
             .sort_by { |group| [group.excessive_count.positive? ? 0 : 1, group.title.downcase] }
    end
  end
end
