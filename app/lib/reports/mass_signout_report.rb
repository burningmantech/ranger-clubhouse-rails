# frozen_string_literal: true

# Every timesheet entry still open, for the page that closes them in one sweep.
# (Upstream: the Ember admin/bulk-signout route, which loads
# `GET timesheet?is_on_duty=1` -- `whereNull('off_duty')` with no year bound.)
#
# Deliberately unbounded in time, unlike OnDutyReport. That report hides
# never-closed entries older than MAX_SHIFT_LOOKBACK so a forgotten sign-in from
# a past event cannot bury whoever is actually still out. Those entries have to
# surface somewhere, and this is the page that can act on them -- so the two
# reports partition the open entries between them, and the boundary is the same
# constant on both sides.
#
# What they are NOT is safe to sign out. Signing off stamps off_duty = now, so a
# 2019 entry closed today records a shift tens of thousands of hours long.
# Upstream pre-checked every row, this one bands them and leaves the stale band
# unchecked; see the view and MassSignoutController#create.
class MassSignoutReport
  # Above this, an open entry is long enough to be worth a second look but is
  # still plausibly a real shift somebody forgot to close this event. Advisory
  # only -- it changes nothing about what "select all" arms, which is why it
  # does not have to agree with OnDutyReport's slot-aware 1.5x excessive rule.
  LONG_THRESHOLD = 24.hours

  Row = Data.define(:timesheet, :elapsed, :credits, :band) do
    def stale? = band == :stale
    def current? = band == :current
    def position = timesheet.position

    # Whether this row can be closed here at all. TimesheetLog belongs_to a
    # required :person, so signing off an entry whose Ranger row is gone cannot
    # write its audit record and raises -- the entry is stuck until someone
    # repairs the data. The page shows it and says so rather than offering a
    # checkbox that would 500 the whole sweep.
    def signable? = person.present?

    # Whether the row starts ticked and "select all" arms it.
    def offered? = !stale? && signable?

    # The Laravel-shared schema carries no FK on person_id either, so a
    # non-optional belongs_to can still read nil. Both come out together
    # because every caller has to hand the pair to person_display_link.
    def person = timesheet.person
    def person_id = timesheet.person_id
  end

  Result = Data.define(:rows) do
    def empty? = rows.empty?
    def total = rows.size

    # A superset of stale, not a sibling of it: a 2019 entry HAS been out over a
    # day, and counting only the :long band rendered "Out over a day: 0" beside
    # "From a past event: 1" -- a stat contradicting the label above it.
    def long_count = rows.count { |row| !row.current? }

    def stale_rows = rows.select(&:stale?)
    def stale_count = stale_rows.size

    # One entry per row, but a Ranger can have left two events open -- the
    # callout names people, so it must not say "Hubcap, Hubcap".
    def stale_people = stale_rows.uniq(&:person_id)
  end

  class << self
    def execute
      entries = open_entries.order(:on_duty).to_a
      credits = TimesheetCredits.credits_by_id(entries)

      rows = entries.map do |timesheet|
        elapsed = elapsed_for(timesheet)
        Row.new(timesheet:,
                elapsed:,
                credits: credits.fetch(timesheet.id, 0.0),
                band: band_for(elapsed))
      end

      Result.new(rows:)
    end

    # The submitted ids split into the entries this page may close and the ones
    # it may not. Lives here, against the same scope +execute+ draws from, so
    # the rows the page offers and the rows the POST accepts cannot come to
    # disagree -- the split AlphaSignOut's header warns about.
    #
    # Unsignable rows are separated rather than dropped so the caller can say
    # what happened to them; see Row#signable?.
    def selectable(ids)
      open_entries.where(id: ids).to_a.partition { |entry| entry.person.present? }
    end

    private

    # Deliberately unbounded in time; see the class comment. Ordered by the
    # caller, because the sweep does not care about order.
    def open_entries
      Timesheet.on_duty_now.includes(:person, :position)
    end

    # Floored at zero, as OnDutyReport#build_entry is and for the same reason:
    # a correction can push on_duty past now, and a negative reaches
    # hour_minute_format as the garbled clock "-2:00".
    #
    # Timesheet#duration is the model's own answer to "how long has this run",
    # memoized, and identical here because every row is still open.
    def elapsed_for(timesheet) = [timesheet.duration, 0].max

    # .to_i on both sides: elapsed is an Integer count of seconds and the
    # thresholds are Durations, and the comparison should not rest on which
    # operand Ruby decides to coerce.
    def band_for(elapsed)
      return :stale if elapsed >= OnDutyReport::MAX_SHIFT_LOOKBACK.to_i
      return :long if elapsed >= LONG_THRESHOLD.to_i

      :current
    end
  end
end
