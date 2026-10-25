# frozen_string_literal: true

# Timesheet entries for one pay period, shaped the way the payroll system wants
# them: clipped to the pay window, and long shifts cut in two around a meal
# break so each half becomes its own pair of punches.
#
# Two things here look like mistakes and are not.
#
# An entry that runs past either end of the window is clipped for the punches,
# but the hours on screen still count the whole shift. Payroll reads the clock
# times, not the totals, and the totals are there so a clerk can recognise the
# shift they remember. Every clipped entry says so in its notes.
#
# An entry no one closed is measured up to the moment the page was built, so its
# hours grow between one run and the next. It is flagged rather than dropped,
# because leaving a Ranger out of payroll is worse than paying them for a shift
# that has to be corrected afterwards.
class PayrollExportReport
  # A shift shorter than this is never cut in two, however the meal-break
  # setting is configured -- below six hours no break is owed.
  MEAL_BREAK_FLOOR_HOURS = 6
  MEAL_BREAK_FLOOR_SECONDS = MEAL_BREAK_FLOOR_HOURS * 3600

  STATUS_LABELS = { still_on_duty: "Still on duty",
                    verified: "Verified",
                    unverified: "Unverified" }.freeze

  # Where a cut shift resumes and stops. The clock times, not durations: these
  # become punches.
  MealBreak = Data.define(:first_on_duty, :first_off_duty,
                          :second_on_duty, :second_off_duty)

  Shift = Data.define(:position_title, :paycode, :verified, :still_on_duty,
                      :orig_on_duty, :orig_off_duty, :orig_duration,
                      :on_duty, :off_duty, :duration, :payable_duration,
                      :meal_break, :notes) do
    def split? = !meal_break.nil?

    def status
      return :still_on_duty if still_on_duty

      verified ? :verified : :unverified
    end

    # Named here, beside the status it describes, so the badge on the page and
    # the column in the checking file cannot come to spell it differently.
    def status_label = STATUS_LABELS[status]

    # Whether this entry is one a clerk should look at before sending money.
    # Anything not yet checked off, and anything still running.
    def needs_review? = still_on_duty || !verified

    def notes_text = notes.join("\n")
  end

  # One person and everything they are owed for in the window. Carries the
  # record itself so the page can link to them.
  PersonRow = Data.define(:record, :shifts) do
    def id = record.id
    def callsign = record.callsign
    def employee_id = record.employee_id

    def total_duration = shifts.sum(&:payable_duration)
    def needs_review_count = shifts.count(&:needs_review?)
    def entry_count = shifts.size
  end

  Result = Data.define(:people, :people_without_ids) do
    # The same report narrowed to one person. Only the listed people narrow:
    # anyone missing an employee id still has to be dealt with either way.
    def for_person(person_id)
      return self if person_id.blank?

      with(people: people.select { |row| row.id == person_id.to_i })
    end

    def empty? = people.empty? && people_without_ids.empty?
    def entry_count = people.sum(&:entry_count)
    def person_count = people.size
    def grand_total = people.sum(&:total_duration)
    def needs_review_count = people.sum(&:needs_review_count)
  end

  class << self
    # break_after_hours of 0 turns meal breaks off entirely.
    def execute(start_time:, end_time:, break_after_hours:, break_duration_minutes:, position_ids:)
      rows = entries_in_window(start_time:, end_time:, position_ids:)
        .group_by(&:person)
        .map do |person, entries|
          shifts = entries.map do |entry|
            build_shift(entry, start_time:, end_time:, break_after_hours:, break_duration_minutes:)
          end

          PersonRow.new(record: person, shifts:)
        end

      # Anyone without an id has to be handled by hand, so they are kept apart
      # rather than mixed into a file payroll would reject.
      with_ids, without_ids = rows.partition { |row| row.employee_id.present? }

      Result.new(people: by_callsign(with_ids), people_without_ids: by_callsign(without_ids))
    end

    private

    # Every entry overlapping the window: it started before the window closed,
    # and it either has not ended or ended after the window opened.
    #
    # The bounds go in as wall-clock strings, not as times. Datetimes are stored
    # as machine-local wall clock, which is not the same zone the application
    # runs in, so a Time bound is rewritten an hour earlier for the months the
    # two zones disagree -- quietly dropping the last hour of every winter pay
    # period, and pulling in entries that ended just before the window began.
    # The column holds wall-clock digits, so wall-clock digits are what it is
    # compared against.
    #
    # Joined so an entry whose person or position row has gone missing drops out
    # instead of failing further down, and preloaded rather than included:
    # combining joins with includes makes one query that selects every column of
    # all three tables, the person's password among them.
    #
    # An employee id of "0" marks someone cleared to ranger but not on the
    # payroll at all. They are not owed anything, so they are not listed. The
    # database decides who that is, as it does for Payroll Missing ID, so a "0 "
    # that report lists as unpaid is left out here too.
    def entries_in_window(start_time:, end_time:, position_ids:)
      off_duty = Timesheet.arel_table[:off_duty]
      employee_id = Person.arel_table[:employee_id]

      Timesheet.joins(:person, :position)
               .preload(:person, :position)
               .where(position_id: position_ids)
               .where(on_duty: ...wall_clock(end_time))
               .where(off_duty.eq(nil).or(off_duty.gt(wall_clock(start_time))))
               .where(employee_id.eq(nil).or(employee_id.not_eq(Person::UNPAID_EMPLOYEE_ID)))
               .ordered_by_on_duty
               .to_a
    end

    def wall_clock(time) = time.strftime("%Y-%m-%d %H:%M:%S")

    def by_callsign(rows) = rows.sort_by { |row| row.callsign.to_s.downcase }

    def build_shift(entry, start_time:, end_time:, break_after_hours:, break_duration_minutes:)
      notes = []
      position = entry.position

      still_on_duty = entry.off_duty.nil?
      notes << "Still on duty" if still_on_duty

      on_duty = entry.on_duty
      # An entry no one closed has no recorded end, so the moment this ran
      # stands in for one. It is clipped to the period below like any other.
      off_duty = entry.off_duty || Current.time

      if start_time > on_duty
        notes << "Truncated start time. Orig was #{shift_time(on_duty)}"
        on_duty = start_time
      end

      if off_duty > end_time
        notes << "Truncated end time. Orig was #{shift_time(off_duty)}"
        off_duty = end_time
      end

      # A period can open after an open entry's only known end -- a clerk
      # preparing next week's run, or a server whose clock is held in the past.
      # Clipping alone leaves that pair inverted, and punches are written out
      # exactly as they stand here, so payroll would read an out before its in.
      off_duty = on_duty if off_duty < on_duty

      duration = seconds_between(on_duty, off_duty)
      if duration < 1.minute
        # Kept rather than dropped: a clerk who sees nothing cannot tell a shift
        # that fell outside the window from one that was never recorded.
        notes.unshift("Entry duration within the report window is under a minute.")
      end

      meal_break = nil
      if position.no_payroll_hours_adjustment?
        notes.unshift("Position set to not adjust hours.")
      elsif break_after_hours.positive?
        meal_break = meal_break_for(on_duty:, duration:, break_after_hours:,
                                    break_duration_minutes:, notes:)
      end

      # An entry no one closed has no recorded span at all -- neither end is a
      # fact -- so both are taken from the pay period. Otherwise a sign-in
      # forgotten at a past event reports years of hours and writes a punch pair
      # stretching back to them.
      orig_on_duty = still_on_duty ? on_duty : entry.on_duty
      orig_off_duty = still_on_duty ? off_duty : entry.off_duty

      Shift.new(position_title: position.title,
                paycode: position.paycode,
                verified: entry.status_verified? || entry.status_approved?,
                still_on_duty:,
                orig_on_duty:,
                orig_off_duty:,
                orig_duration: seconds_between(orig_on_duty, orig_off_duty),
                on_duty:,
                off_duty:,
                duration:,
                # What the punches add up to, which is what payroll will pay:
                # the time inside the period, less the unpaid break when the
                # shift was cut. Counted from the clipped span rather than the
                # whole shift so the totals on the page can be reconciled
                # against the file, and so more time inside the period can
                # never be worth less than a shorter overlap.
                payable_duration: meal_break ? duration - (break_duration_minutes * 60) : duration,
                meal_break:,
                notes:)
    end

    # Where to cut, or nil with a note saying why the shift was left whole.
    # Appends to notes.
    def meal_break_for(on_duty:, duration:, break_after_hours:, break_duration_minutes:, notes:)
      break_after_seconds = break_after_hours * 3600
      break_seconds = break_duration_minutes * 60

      if duration < MEAL_BREAK_FLOOR_SECONDS
        if duration > break_after_seconds
          notes << "Duration is less than #{MEAL_BREAK_FLOOR_HOURS} hours. No meal break inserted."
        end
        return nil
      end

      # Whole hours only, so a shift a few minutes over the threshold is left
      # alone rather than cut for the sake of it.
      if (duration / 3600) <= break_after_hours
        notes << "Duration did not exceed the break-after threshold by a full hour. No meal break inserted."
        return nil
      end

      remaining = duration - break_after_seconds - break_seconds
      unless remaining.positive?
        notes << "Duration is not long enough to fit both halves of the shift plus the meal break. No meal break inserted."
        return nil
      end

      first_off_duty = on_duty + break_after_seconds
      second_on_duty = first_off_duty + break_seconds

      MealBreak.new(first_on_duty: on_duty,
                    first_off_duty:,
                    second_on_duty:,
                    second_off_duty: second_on_duty + remaining)
    end

    # Floored at zero. A sign-in mistyped into the future would otherwise run
    # backwards and be reported as negative hours.
    def seconds_between(from, to) = (to - from).to_i.clamp(0..)

    # With the year: the entry a clipping note is warning about is often one
    # left open at a past event, and without a year "Sep 01" reads as this week.
    def shift_time(time) = time.strftime(DateTimeHelper::MONTH_DAY_TIME_YEAR)
  end
end
