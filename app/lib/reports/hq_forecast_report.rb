# frozen_string_literal: true

# How busy the HQ window is expected to be, period by period, and who is on
# duty to handle it.
#
# Shifts starting are people arriving to check in; shifts ending are people
# coming back to check out. Counting both against the HQ desks on duty at the
# same hour says whether HQ is staffed for the traffic it is about to get.
class HqForecastReport
  # The desks HQ runs. Their shifts set the hours the report covers, and their
  # sign-ups fill the staffing columns.
  #
  # Listed in the order the page prints them, which reads down the room from
  # the person running it to the person fetching for it. A pre-event desk sits
  # beside the one it runs ahead of, before the event opens.
  Desk = Struct.new(:key, :position_id, :title)

  DESKS = [
    Desk.new(:leads, Position::HQ_LEAD, "HQ Lead"),
    Desk.new(:pre_event_leads, Position::HQ_LEAD_PRE_EVENT, "HQ Lead - Pre-event"),
    Desk.new(:shorts, Position::HQ_SHORT, "HQ Short"),
    Desk.new(:windows, Position::HQ_WINDOW, "HQ Window"),
    Desk.new(:pre_event_windows, Position::HQ_WINDOW_PRE_EVENT, "HQ Window - Pre-event"),
    Desk.new(:runners, Position::HQ_RUNNER, "HQ Runner")
  ].freeze

  DESK_KEYS = DESKS.map(&:key).freeze
  HQ_POSITION_IDS = DESKS.map(&:position_id).freeze

  # A runner is fetching things, not answering the window, so a period covered
  # by runners alone still has no one to check anyone in or out. The pre-event
  # lead and window answer it the same as their event-time twins.
  COVERAGE_KEYS = %i[leads pre_event_leads shorts windows pre_event_windows].freeze

  # The spreadsheet's staffing columns: the pre-event desks lead, since they
  # run first, before the event opens, and the rest follow in the page's order.
  CSV_DESKS = DESKS.partition { |desk| desk.key.start_with?("pre_event") }.flatten.freeze

  # Training shifts run their own check-in at the training site, so they are
  # not traffic the HQ window will see.
  TRAINING_POSITION_IDS = [
    Position::TRAINING,
    Position::TRAINER,
    Position::TRAINER_ASSOCIATE,
    Position::TRAINER_UBER
  ].freeze

  # How wide a period can be, in minutes. Anything else -- a stale bookmark, a
  # typed URL -- falls back to the default rather than dividing the day into
  # buckets no one asked for.
  INTERVALS = [15, 30, 60, 180, 360].freeze
  DEFAULT_INTERVAL = 60

  # As many rows as the report will ever draw. Four weeks of quarter hours --
  # longer than any event, and far past what anybody reads.
  MAX_PERIODS = 2688

  ALL_DAYS = UiComponents::FilterBarHelper::ALL_FILTER

  # One row: how many people are expected, and who is on duty for them.
  #
  # hq_open says HQ has a shift scheduled at some desk during this period,
  # whether or not anyone signed up for it. With none, the window is shut --
  # pre-event HQ closes overnight, and a burn can run after HQ has gone home
  # -- and a closed window is not an uncovered one.
  Period = Struct.new(:begins, :checkin, :checkout, :staffing, :hq_open) do
    # Everyone walking up to the window in this period, arriving or leaving.
    # The chart's traffic bars are drawn from this.
    def demand = checkin + checkout

    def count_for(key) = staffing.fetch(key, 0)

    def unstaffed? = hq_open && COVERAGE_KEYS.none? { |key| count_for(key).positive? }

    def empty? = demand.zero? && DESK_KEYS.none? { |key| count_for(key).positive? }
  end

  # One calendar day of HQ's hours, which is how the page breaks the report
  # up. Its chart runs midnight to midnight, however long HQ is open on it;
  # the end is held, since every mark on the chart is placed against it.
  Day = Struct.new(:key, :label, :starts) do
    def ends = @ends ||= starts + 1.day
  end

  # One of HQ's own shifts, drawn as a bar on the chart of every day it runs
  # through: when it runs, and how many of its places are taken.
  Shift = Struct.new(:id, :desk, :begins, :ends, :signups, :max)

  # One burn and the traffic it brings. Several shifts can start together --
  # the burn and its perimeter -- so the title names all of them. Its desks are
  # the ones with a shift in its periods, the only columns worth drawing.
  Burn = Struct.new(:key, :title, :periods, :desks)

  # The periods run in time order, one list for the whole report, apart from
  # the days: a wide period can begin the evening before the day it mostly
  # falls on, so no day owns it.
  Result = Struct.new(:interval, :periods, :days, :shifts) do
    def any? = days.any?

    def unstaffed_count = periods.count(&:unstaffed?)

    def checkin_total = periods.sum(&:checkin)

    # The period the most people are expected to check in for. What the page
    # warns about is arrivals: a queue forms when people show up, not when they
    # leave. Nothing when no one is expected all year -- the busiest of a dozen
    # noughts is an arbitrary hour dressed up as an answer.
    def busiest
      peak = periods.max_by(&:checkin)
      peak if peak&.checkin&.positive?
    end

    def day_options = days.map { |day| [day.label, day.key] }

    def day_keys = days.map(&:key)

    # The days the page draws: all of them, or the one asked for.
    def filtered_days(key) = key == ALL_DAYS ? days : days.select { |day| day.key == key }

    # Everything reaching into one day's chart: a three- or six-hour period can
    # start the evening before, and a shift can run on past midnight into it.
    #
    # Found by searching for the first period rather than reading the whole
    # year for every day drawn -- which is why the periods are kept in one
    # list in time order.
    def periods_on(day)
      earliest = day.starts - interval.minutes
      first = periods.bsearch_index { |period| period.begins > earliest } || periods.size
      periods[first..].take_while { |period| period.begins < day.ends }
    end

    def shifts_on(day) = shifts.select { |shift| shift.begins < day.ends && shift.ends > day.starts }

    # The gaps a day's chart shows, counted from what it draws: the heading
    # and the hatching beneath it have to agree. A period reaching across
    # midnight is a gap on both of its days; the year's total counts it once.
    def unstaffed_on(day) = periods_on(day).count(&:unstaffed?)
  end

  # Everyone signed up at one desk for one period, with whether they are marked
  # on site and the years they have put in at each HQ desk (position id to a
  # list of years), so the dialog can say who knows the window already.
  Signup = Struct.new(:person_id, :callsign, :begins, :on_site, :hq_years)

  class << self
    # Anything that is not one of the widths on offer falls back to the
    # default. Parsed rather than converted: a nested value arrives as
    # something with no number in it at all, and asking it for one would fail
    # instead of landing on the default.
    def normalize_interval(value)
      minutes = parse_id(value)
      INTERVALS.include?(minutes) ? minutes : DEFAULT_INTERVAL
    end

    # A number from a URL, or nil. Always base ten: Integer() on its own reads
    # "010" as octal eight and "0x1A" as hex, so a hand-typed id would open
    # something other than what its digits say.
    def parse_id(value) = Integer(value.to_s, 10, exception: false)

    def interval_options = INTERVALS.map { |minutes| [interval_label(minutes), minutes] }

    def interval_label(minutes)
      return "#{minutes} minutes" if minutes < 60

      hours = minutes / 60
      "#{hours} #{"hour".pluralize(hours)}"
    end

    def desk_for(position_id) = DESKS.find { |desk| desk.position_id == position_id }

    # The whole year: every period HQ is open, with the traffic and the staffing
    # for each.
    def execute(year:, interval:)
      minutes = normalize_interval(interval)
      seconds = minutes * 60
      hq_slots = slots_for(year, HQ_POSITION_IDS)
      hours = hq_hours(hq_slots)
      return Result.new(minutes, [], [], []) if hours.nil?

      opening, closing = period_bounds(hours, seconds)
      periods = period_skeleton(opening, closing, seconds)
      count_visits(periods, year, hours, seconds)
      signed_up, scheduled = duty_series(hq_slots, hours, seconds)
      periods.each_value { |period| put_on_duty(period, signed_up, scheduled) }

      Result.new(minutes, trim_trailing_empty(periods).values, days_for(hours, closing),
                 shifts_for(hq_slots))
    end

    # The same forecast read burn by burn: what each burn sends to the window,
    # and who was on duty when it did.
    def burn_perimeters(year:, interval:)
      seconds = normalize_interval(interval) * 60

      slots = slots_for(year, [Position::BURN_PERIMETER])
      return [] if slots.empty?

      hq_slots = slots_for(year, HQ_POSITION_IDS)
      signed_up, scheduled = duty_series(hq_slots, hq_hours(hq_slots), seconds)

      slots.group_by { |slot| slot[:begins] }.sort_by(&:first).map do |begins, group|
        periods = burn_periods(group, signed_up, scheduled, seconds)
        Burn.new(begins.strftime("%Y%m%d%H%M"), burn_title(begins, group), periods,
                 desks_scheduled(scheduled, periods))
      end
    end

    # Who is signed up at one desk during one period. The window is the period
    # itself, and a shift counts when any part of it lands inside.
    def people_in_period(position_id:, period:, interval:)
      seconds = normalize_interval(interval) * 60
      ends = period + seconds

      Person.joins(:slot)
            .where(slot: { position_id:, begins_year: period.year, active: true })
            .where("slot.begins < ? AND slot.ends > ?", ends, period)
            .pluck("person.id", "person.callsign", "slot.begins", "person.on_site")
            # in_time_zone because a datetime named through a join comes back
            # in the machine's own zone rather than the one the page reads in.
            .map { |id, callsign, begins, on_site| Signup.new(id, callsign, begins.in_time_zone, on_site) }
            .sort_by { |signup| [signup.begins, signup.callsign.to_s.downcase] }
            .then { |signups| with_hq_years(signups) }
    end

    # One HQ shift and everyone signed up for it: exactly the people its bar
    # counts, whatever else overlaps it.
    #
    # Nothing for a shift at any other desk. The dialog is HQ's own roster,
    # not a way to look up who is on any shift of the event.
    def people_on_shift(slot_id)
      slot = Slot.active.for_position(HQ_POSITION_IDS).find_by(id: slot_id)
      return unless slot

      people = slot.sign_ups.pluck(:id, :callsign, :on_site)
                   .map { |id, callsign, on_site| Signup.new(id, callsign, slot.begins, on_site) }
                   .sort_by { |signup| signup.callsign.to_s.downcase }
                   .then { |signups| with_hq_years(signups) }
      shift = Shift.new(slot.id, desk_for(slot.position_id), slot.begins, slot.ends, people.size, slot.max)
      [shift, people]
    end

    # The report as a spreadsheet. The day filter is a way of reading the page
    # rather than a different report, so the file always holds every period.
    def csv_rows(result)
      rows = [["Time (#{interval_label(result.interval)} interval)", "Check In", "Check Out"] +
              CSV_DESKS.map(&:title)]

      result.periods.each do |period|
        rows << [stamp(period.begins), period.checkin, period.checkout] +
                CSV_DESKS.map { |desk| period.count_for(desk.key) }
      end

      rows
    end

    private

    # Fill in each signup's years at the HQ desks, from completed timesheet
    # entries, in one query for the whole list.
    def with_hq_years(signups)
      years = Timesheet.where(person_id: signups.map(&:person_id), position_id: HQ_POSITION_IDS)
                       .with_off_duty
                       .distinct
                       .pluck(:person_id, :position_id, Arel.sql("YEAR(on_duty)"))
                       .group_by(&:first)
                       .transform_values { |rows| rows.group_by { |row| row[1] }.transform_values { |r| r.map(&:last).sort } }
      signups.each { |signup| signup.hq_years = years.fetch(signup.person_id, {}) }
    end

    # Shift times go out as they are read. They are the clock on the wall where
    # the shift happens, and moving them would rename the hour being asked about.
    def stamp(time) = time.strftime(DateTimeHelper::CSV_TIME)

    # When HQ opens and closes for the year, to the minute.
    #
    # Kept unrounded: which shifts count as traffic is decided against these,
    # so the year's totals stay the same however the day is cut up. Only the
    # rows are widened to whole periods.
    def hq_hours(hq_slots)
      return nil if hq_slots.empty?

      [hq_slots.pluck(:begins).min, hq_slots.pluck(:ends).max]
    end

    # The rows HQ's hours are drawn on, widened out to whole periods.
    #
    # A single shift with a mistyped end date can otherwise ask for a row every
    # quarter hour for months. The report is one event long, so a span past
    # that is bad data rather than a very long event, and it is cut off at a
    # length no one can read past anyway.
    def period_bounds(hours, seconds)
      opening = floor_to(hours.first, seconds)
      closing = ceil_to(hours.last, seconds)
      [opening, [closing, opening + (MAX_PERIODS * seconds)].min]
    end

    # The closing period is included so a shift ending exactly on it still has a
    # row to land on; trim_trailing_empty takes it back when nothing did.
    def period_skeleton(opening, closing, seconds)
      periods = {}
      time = opening

      while time <= closing
        periods[time] = Period.new(time, 0, 0, {}, false)
        time += seconds
      end

      periods
    end

    # Arrivals and departures, counted from the shifts that cause them.
    #
    # A shift counts only when it fits inside HQ's hours end to end. One
    # hanging over either edge belongs to a day this report does not cover.
    # Tested against the real hours rather than the widened rows, so the same
    # shifts count however the day is cut up.
    def count_visits(periods, year, hours, seconds)
      open_at, close_at = hours

      slots_for(year).each do |slot|
        next if HQ_POSITION_IDS.include?(slot[:position_id])
        next if TRAINING_POSITION_IDS.include?(slot[:position_id])
        next if slot[:begins] < open_at || slot[:ends] > close_at

        checkin = periods[floor_to(slot[:begins], seconds)]
        checkout = periods[floor_to(slot[:ends], seconds)]
        # Both rows exist for any shift inside HQ's hours. A report cut short
        # at MAX_PERIODS is the exception, and a shift past the cut simply has
        # nowhere to land.
        checkin.checkin += slot[:signups] if checkin
        checkout.checkout += slot[:signups] if checkout
      end
    end

    # Two counts for each desk, period by period, over HQ's hours: the people
    # signed up, and the shifts scheduled whether anyone signed up or not. The
    # second is what says HQ is open at all, and which desks a burn's table
    # draws -- counted by the same rule as the first, so a column is never
    # drawn that its cells would not fill. Nothing either way without HQ
    # shifts.
    def duty_series(hq_slots, hours, seconds)
      return [{}, {}] if hours.nil?

      opening, closing = period_bounds(hours, seconds)
      [desk_series(hq_slots, opening, closing, seconds) { |slot| slot[:signups] },
       desk_series(hq_slots, opening, closing, seconds) { 1 }]
    end

    # A period's staffing, and whether HQ has anything scheduled in it. Beyond
    # the series -- past HQ's hours, or past a MAX_PERIODS cut -- every count
    # is nought and the window is shut.
    def put_on_duty(period, signed_up, scheduled)
      period.staffing = signed_up.transform_values { |totals| totals.fetch(period.begins, 0) }
      period.hq_open = scheduled.values.any? { |totals| totals.fetch(period.begins, 0).positive? }
      period
    end

    # A running count at each desk for each period, of whatever the block
    # weighs a shift at.
    #
    # Read as a running count rather than by asking who overlaps each period:
    # a period gains whoever starts in it and loses whoever has finished, and
    # the rest carry over. A shift counts for every period any part of it
    # covers, which is the same question the sign-up list behind each count
    # answers -- so the number and the names agree.
    #
    # The desks are handed in rather than read once per column: HQ's own
    # shifts are what set the report's hours, so the caller holds them already.
    def desk_series(hq_slots, opening, closing, seconds)
      by_desk = hq_slots.group_by { |slot| slot[:position_id] }

      DESKS.to_h do |desk|
        starts = Hash.new(0)
        finishes = Hash.new(0)

        by_desk.fetch(desk.position_id, []).each do |slot|
          weight = yield slot
          starts[floor_to(slot[:begins], seconds)] += weight
          # Counted out at the end of the period the shift finishes in, not the
          # start of it. Somebody on until half past is still at the desk for
          # that period, and a shift that begins and ends inside one period
          # would otherwise be added and taken away in the same breath and
          # never appear at all.
          finishes[ceil_to(slot[:ends], seconds)] += weight
        end

        [desk.key, running_totals(starts, finishes, opening, closing, seconds)]
      end
    end

    # HQ's shifts as the chart draws them, in the order they start.
    def shifts_for(hq_slots)
      hq_slots.sort_by { |slot| slot[:begins] }.map do |slot|
        Shift.new(slot[:id], desk_for(slot[:position_id]), slot[:begins], slot[:ends],
                  slot[:signups], slot[:max])
      end
    end

    def running_totals(starts, finishes, opening, closing, seconds)
      totals = {}
      on_duty = 0
      time = opening

      while time <= closing
        on_duty += starts[time]
        on_duty -= finishes[time]
        totals[time] = on_duty
        time += seconds
      end

      totals
    end

    # One burn's rows: only the periods it actually sends people through,
    # carrying whatever HQ staffing those periods had.
    def burn_periods(group, signed_up, scheduled, seconds)
      periods = {}

      group.each do |slot|
        burn_period(periods, floor_to(slot[:begins], seconds), signed_up, scheduled).checkin +=
          slot[:signups]
        burn_period(periods, floor_to(slot[:ends], seconds), signed_up, scheduled).checkout +=
          slot[:signups]
      end

      periods.keys.sort.map { |time| periods[time] }
    end

    # The desks with a shift in any of these periods, in the order the page
    # prints them. A desk with nothing scheduled is left off rather than drawn
    # as a column of noughts -- a pre-event desk beside a burn, say.
    def desks_scheduled(scheduled, periods)
      DESKS.select do |desk|
        totals = scheduled.fetch(desk.key, {})
        periods.any? { |period| totals.fetch(period.begins, 0).positive? }
      end
    end

    # Burns starting together are one entry, so the title names all of them.
    #
    # The night is part of the name: the rows below carry only the hour, and
    # two burns with nothing written on them would otherwise be two sections
    # called the same thing.
    def burn_title(begins, group)
      named = group.filter_map { |slot| slot[:description].presence }.uniq.join(" / ")
      "#{named.presence || "Burn Perimeter"} — #{begins.strftime(DateTimeHelper::DAY_LABEL)}"
    end

    def burn_period(periods, time, signed_up, scheduled)
      periods[time] ||= put_on_duty(Period.new(time, 0, 0, {}, false), signed_up, scheduled)
    end

    # The closing period is added so a shift ending on it is not lost. When
    # nothing landed there it is an empty row on every report, so it goes back.
    # Only that one, and only when empty: a quiet hour earlier in the day is
    # part of the answer.
    def trim_trailing_empty(periods)
      last = periods.keys.last
      periods.delete(last) if last && periods[last].empty?
      periods
    end

    # Every shift of the year with the number of people signed up for it.
    #
    # Sign-ups are counted from the sign-up rows rather than read off the
    # slot's own tally, which only the scheduling pages keep up to date.
    #
    # Only live shifts: one no one can sign up for is not traffic anybody has
    # to answer for, and a stray draft would otherwise set the hours the whole
    # report runs between.
    def slots_for(year, position_ids = nil)
      scope = Slot.active.for_year(year)
      scope = scope.for_position(position_ids) if position_ids

      counts = PersonSlot.where(slot_id: scope.select(:id)).group(:slot_id).count

      scope.pluck(:id, :position_id, :begins, :ends, :description, :max)
           .map { |id, position_id, begins, ends, description, max|
             { id:, position_id:, begins:, ends:, description:, max:,
               signups: counts.fetch(id, 0) }
           }
    end

    # Periods are cut on a fixed grid running from the epoch, which is what the
    # report has always used.
    #
    # For the widths people pick -- a quarter hour, a half, an hour -- that grid
    # and the clock agree, so a one-hour period starts on the hour. The three-
    # and six-hour widths are cut on the same grid rather than from midnight, so
    # they start at whatever hour the offset puts them on; see the test that
    # pins it.
    def floor_to(time, seconds) = Time.zone.at(time.to_i - (time.to_i % seconds))

    def ceil_to(time, seconds)
      floored = floor_to(time, seconds)
      floored == time ? floored : floored + seconds
    end

    # A day for every date HQ is open on, from its first shift to its last --
    # taken from HQ's hours rather than the periods, which at three or six
    # hours can begin the evening before HQ opens and end with the empty one
    # trimmed after it closes. A shift ending on the stroke of midnight is
    # done before the next day starts. Cut short with the periods when
    # MAX_PERIODS cuts them.
    #
    # Labelled the way the other schedule reports label a day, so the same day
    # reads the same wherever it is offered.
    def days_for(hours, closing)
      last = [hours.last, closing].min - 1

      (hours.first.to_date..last.to_date).map do |date|
        starts = date.in_time_zone
        Day.new(starts.strftime("%m%d"), starts.strftime(DateTimeHelper::DAY_LABEL), starts)
      end
    end
  end
end
