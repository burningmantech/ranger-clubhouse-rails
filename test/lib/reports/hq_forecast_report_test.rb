# frozen_string_literal: true

require "test_helper"

class HqForecastReportTest < ActiveSupport::TestCase
  include TrainingSlotTestHelper

  YEAR = 2024

  setup do
    Current.reset

    @window = ensure_position(Position::HQ_WINDOW, "HQ Window")
    @lead = ensure_position(Position::HQ_LEAD, "HQ Lead")
    @short = ensure_position(Position::HQ_SHORT, "HQ Short")
    @runner = ensure_position(Position::HQ_RUNNER, "HQ Runner")
    @pre_event_lead = ensure_position(Position::HQ_LEAD_PRE_EVENT, "HQ Lead - Pre-event")
    @pre_event_window = ensure_position(Position::HQ_WINDOW_PRE_EVENT, "HQ Window - Pre-event")
    @dirt = ensure_position(Position::DIRT, "Dirt")
    @training = ensure_position(Position::TRAINING, "Training")
    @burn = ensure_position(Position::BURN_PERIMETER, "Burn Perimeter")

    @ranger = person(:active_ranger)
    @other = person(:echelon_ranger)
  end

  teardown { Current.reset }

  def ensure_position(id, title)
    Position.find_or_create_by!(id:) { |position| position.title = title }
  end

  def at(hour, minute = 0, day: 26) = Time.zone.local(YEAR, 8, day, hour, minute, 0)

  def sign_up(person, slot) = PersonSlot.create!(person_id: person.id, slot_id: slot.id)

  # One HQ window shift sets the hours every test below runs inside.
  def open_hq(begins: at(6), ends: at(18), position: @window, people: [])
    slot = create_slot(position, begins:, ends:)
    people.each { |person| sign_up(person, slot) }
    slot
  end

  def forecast(interval: 60) = HqForecastReport.execute(year: YEAR, interval:)

  def period_at(result, time) = result.periods.find { |period| period.begins == time }

  # --- The hours the report covers ----------------------------------------

  test "no HQ shifts means no report at all" do
    create_slot(@dirt, begins: at(9), ends: at(17))

    assert_not forecast.any?
  end

  test "the report runs from the first HQ shift to the last" do
    open_hq(begins: at(6), ends: at(10))
    # Something has to land in the closing period or it is trimmed away.
    sign_up(@ranger, create_slot(@dirt, begins: at(7), ends: at(10)))

    result = forecast

    assert_equal at(6), result.periods.first.begins
    assert_equal at(10), result.periods.last.begins
  end

  test "ragged HQ hours widen out to whole periods" do
    open_hq(begins: at(6, 20), ends: at(9, 40))

    result = forecast

    assert_equal at(6), result.periods.first.begins
    # 09:40 rounds up to the 10:00 boundary, and that period is empty, so it
    # goes back off again.
    assert_equal at(9), result.periods.last.begins
  end

  test "a closing period holding nothing is dropped, but a quiet hour mid-report is kept" do
    open_hq(begins: at(6), ends: at(9))
    sign_up(@ranger, create_slot(@dirt, begins: at(6), ends: at(8)))

    result = forecast

    assert_equal [at(6), at(7), at(8)], result.periods.map(&:begins)
    # 07:00 has no arrivals and no departures but HQ is open, so it stays.
    assert_equal 0, period_at(result, at(7)).demand
  end

  # --- Check-ins and check-outs -------------------------------------------

  test "a shift starting and ending inside HQ hours is counted at both ends" do
    open_hq
    slot = create_slot(@dirt, begins: at(9), ends: at(13))
    sign_up(@ranger, slot)
    sign_up(@other, slot)

    result = forecast

    assert_equal 2, period_at(result, at(9)).checkin
    assert_equal 2, period_at(result, at(13)).checkout
  end

  test "sign-ups are counted from the sign-up rows, not the slot's own tally" do
    open_hq
    slot = create_slot(@dirt, begins: at(9), ends: at(13))
    sign_up(@ranger, slot)
    slot.update_columns(signed_up: 99)

    assert_equal 1, period_at(forecast, at(9)).checkin
  end

  test "HQ's own shifts are traffic for no one" do
    open_hq(people: [@ranger])

    assert_equal 0, forecast.periods.sum(&:checkin)
  end

  test "training shifts check in at the training site, not the window" do
    open_hq
    sign_up(@ranger, create_slot(@training, begins: at(9), ends: at(13)))

    assert_equal 0, forecast.periods.sum(&:checkin)
  end

  # Burn perimeter shifts are traffic like any other shift. They also get their
  # own page, which answers a different question about the same sign-ups.
  test "burn perimeter shifts count as traffic on the main report" do
    open_hq
    sign_up(@ranger, create_slot(@burn, begins: at(9), ends: at(13)))

    assert_equal 1, period_at(forecast, at(9)).checkin
  end

  test "a shift hanging over either edge of HQ hours is left out entirely" do
    open_hq(begins: at(8), ends: at(18))
    sign_up(@ranger, create_slot(@dirt, begins: at(6), ends: at(12)))

    result = forecast

    assert_equal 0, result.periods.sum(&:checkin)
    assert_equal 0, result.periods.sum(&:checkout)
  end

  test "arrivals land in the period their shift starts in" do
    open_hq
    sign_up(@ranger, create_slot(@dirt, begins: at(9, 45), ends: at(13, 15)))

    result = forecast

    assert_equal 1, period_at(result, at(9)).checkin
    assert_equal 1, period_at(result, at(13)).checkout
  end

  test "a narrower period splits the same arrivals into their own quarters" do
    open_hq
    sign_up(@ranger, create_slot(@dirt, begins: at(9, 45), ends: at(13)))

    result = forecast(interval: 15)

    assert_equal 1, period_at(result, at(9, 45)).checkin
    assert_equal 0, period_at(result, at(9, 30)).checkin
  end

  # --- Who is on duty ------------------------------------------------------

  test "staffing carries forward until the shift ends" do
    # The window shift holds the report open past the lead's last hour, so
    # there is a row to check the handover on.
    open_hq(begins: at(6), ends: at(12), people: [@other])
    open_hq(begins: at(6), ends: at(10), position: @lead, people: [@ranger])

    result = forecast

    assert_equal 1, period_at(result, at(6)).count_for(:leads)
    assert_equal 1, period_at(result, at(9)).count_for(:leads)
    # The shift ends at 10:00, so that period is already handed over.
    assert_equal 0, period_at(result, at(10)).count_for(:leads)
  end

  test "a second shift starting adds to the count already on duty" do
    open_hq(begins: at(6), ends: at(12), people: [@ranger])
    open_hq(begins: at(8), ends: at(12), people: [@other])

    result = forecast

    assert_equal 1, period_at(result, at(7)).count_for(:windows)
    assert_equal 2, period_at(result, at(8)).count_for(:windows)
  end

  test "each desk is counted on its own" do
    open_hq(begins: at(6), ends: at(12))
    open_hq(begins: at(6), ends: at(12), position: @lead, people: [@ranger])
    open_hq(begins: at(6), ends: at(12), position: @runner, people: [@other])

    period = period_at(forecast, at(8))

    assert_equal 1, period.count_for(:leads)
    assert_equal 1, period.count_for(:runners)
    assert_equal 0, period.count_for(:shorts)
  end

  # --- Which periods are flagged ------------------------------------------

  test "a period with no one at any desk is flagged" do
    open_hq(begins: at(6), ends: at(12))

    assert_predicate period_at(forecast, at(8)), :unstaffed?
  end

  # Counting the gaps is what the page is for, so the tally has to be a real
  # count and not a nought that happens to be right.
  test "the gaps are counted, by day and for the year" do
    # HQ open right through to the next morning, with a lead on the whole time
    # apart from two hours on the first day.
    open_hq(begins: at(6), ends: at(10, day: 27))
    open_hq(begins: at(6), ends: at(8), position: @lead, people: [@ranger])
    open_hq(begins: at(10), ends: at(10, day: 27), position: @lead, people: [@other])

    result = forecast

    # 08:00 and 09:00 on the 26th, and nothing on the 27th.
    assert_equal 2, result.unstaffed_count
    assert_equal [2, 0], result.days.map { |day| result.unstaffed_on(day) }
  end

  # Pre-event HQ shuts overnight. With nothing scheduled at any desk the window
  # is closed, and a closed window is not an uncovered one.
  test "an hour with no HQ shift at any desk is closed, not a gap" do
    open_hq(begins: at(8), ends: at(16), position: @pre_event_window, people: [@ranger])
    open_hq(begins: at(8, day: 27), ends: at(16, day: 27), position: @pre_event_window, people: [@other])

    result = forecast

    assert_not_predicate period_at(result, at(22)), :hq_open
    assert_equal 0, result.unstaffed_count
  end

  # The heading over a day and the hatching beneath it count the same periods,
  # the evening before's included.
  test "a day's gap count covers every period its chart draws" do
    open_hq(begins: at(20), ends: at(10, day: 27))

    result = forecast(interval: 360)

    assert_equal 2, result.unstaffed_on(result.days.last)
    assert_equal 3, result.unstaffed_count
  end

  # A shift finishing part way through a period is still at the desk for it.
  test "a shift is on duty for every period any part of it covers" do
    open_hq(begins: at(6), ends: at(12), people: [@other])
    open_hq(begins: at(6), ends: at(9, 30), position: @lead, people: [@ranger])

    result = forecast

    assert_equal 1, period_at(result, at(9)).count_for(:leads)
    assert_equal 0, period_at(result, at(10)).count_for(:leads)
  end

  # Added and taken away in the same breath, a short shift used to vanish.
  test "a shift beginning and ending inside one period still counts" do
    open_hq(begins: at(0), ends: at(23), people: [@other])
    open_hq(begins: at(12), ends: at(16), position: @lead, people: [@ranger])

    # A six-hour period swallows the whole four-hour shift.
    assert_equal 1, forecast(interval: 360).periods.map { |p| p.count_for(:leads) }.max
  end

  # The number on a cell and the list it opens have to be answering the same
  # question, or the reader is told two different things about one period.
  test "a staffing count matches the list of people behind it" do
    open_hq(begins: at(6), ends: at(9, 30), position: @lead, people: [@ranger])
    open_hq(begins: at(9), ends: at(14), position: @lead, people: [@other])

    [15, 60, 180].each do |minutes|
      forecast(interval: minutes).periods.each do |period|
        listed = HqForecastReport.people_in_period(position_id: Position::HQ_LEAD,
                                                   period: period.begins, interval: minutes)

        assert_equal listed.size, period.count_for(:leads),
                     "#{minutes}-minute period #{period.begins} disagrees with its list"
      end
    end
  end

  # The headline figure has to be about the year, not about how the day was
  # sliced to look at it.
  test "the year's arrivals do not change with the period width" do
    open_hq(begins: at(6, 20), ends: at(17, 40))
    sign_up(@ranger, create_slot(@dirt, begins: at(7), ends: at(15)))
    sign_up(@other, create_slot(@dirt, begins: at(6, 30), ends: at(17)))

    totals = HqForecastReport::INTERVALS.map { |minutes| forecast(interval: minutes).checkin_total }

    assert_equal [totals.first] * HqForecastReport::INTERVALS.size, totals
  end

  # A shift no one can sign up for is not traffic and does not set the hours.
  test "shifts that are not live are left out" do
    open_hq(begins: at(6), ends: at(10), people: [@ranger])
    dead = create_slot(@window, begins: at(1), ends: at(3))
    dead.update_columns(active: false)
    quiet = create_slot(@dirt, begins: at(7), ends: at(8))
    sign_up(@other, quiet)
    quiet.update_columns(active: false)

    result = forecast

    assert_equal at(6), result.periods.first.begins
    assert_equal 0, result.checkin_total
  end

  test "a runner alone does not answer the window" do
    open_hq(begins: at(6), ends: at(12))
    open_hq(begins: at(6), ends: at(12), position: @runner, people: [@ranger])

    assert_predicate period_at(forecast, at(8)), :unstaffed?
  end

  test "a lead, a short, or a window, pre-event or not, each answer the window on their own" do
    [@lead, @pre_event_lead, @short, @window, @pre_event_window].each do |position|
      Slot.destroy_all
      open_hq(begins: at(6), ends: at(12))
      open_hq(begins: at(6), ends: at(12), position:, people: [@ranger])

      assert_not_predicate period_at(forecast, at(8)), :unstaffed?,
                           "#{position.title} should count as coverage"
    end
  end

  # --- Days and totals -----------------------------------------------------

  test "periods are grouped into the days they fall on" do
    open_hq(begins: at(20), ends: at(4, day: 27))

    assert_equal 2, forecast.days.size
  end

  test "the summary counts arrivals, gaps, and the busiest period" do
    open_hq(begins: at(6), ends: at(10), people: [@ranger])
    sign_up(@ranger, create_slot(@dirt, begins: at(7), ends: at(9)))
    sign_up(@other, create_slot(@dirt, begins: at(7), ends: at(9)))

    result = forecast

    assert_equal 2, result.checkin_total
    assert_equal at(7), result.busiest.begins
    assert_equal 0, result.unstaffed_count
  end

  # The busiest of a dozen noughts is an arbitrary hour dressed up as an answer.
  test "no arrivals all year means no busiest period to name" do
    open_hq(begins: at(6), ends: at(10), people: [@ranger])

    assert_nil forecast.busiest
  end

  # --- The day's chart -----------------------------------------------------

  test "HQ's own shifts come with the report, with their sign-ups and places" do
    slot = open_hq(begins: at(6), ends: at(14), people: [@ranger, @other])
    create_slot(@dirt, begins: at(7), ends: at(9))

    shift = forecast.shifts.sole

    assert_equal [slot.id, "HQ Window", at(6), at(14), 2, 20],
                 [shift.id, shift.desk.title, shift.begins, shift.ends, shift.signups, shift.max]
  end

  test "a day's chart holds every shift running through any part of it" do
    open_hq(begins: at(6), ends: at(12))
    create_slot(@runner, begins: at(20), ends: at(0, day: 27))
    create_slot(@window, begins: at(22), ends: at(2, day: 27))
    create_slot(@lead, begins: at(2, day: 27), ends: at(6, day: 27))

    result = forecast
    monday, tuesday = result.days

    assert_equal [at(6), at(20), at(22)], result.shifts_on(monday).map(&:begins)
    # The night shift runs on into Tuesday; the runner finishing on the stroke
    # of midnight does not.
    assert_equal [at(22), at(2, day: 27)], result.shifts_on(tuesday).map(&:begins)
  end

  # At three or six hours the period after HQ closes is empty and dropped; the
  # day HQ's last shift ends on still gets its chart.
  test "every day HQ is open on gets a chart, whatever the period width" do
    open_hq(begins: at(20), ends: at(1, day: 27))

    [60, 180, 360].each do |minutes|
      result = forecast(interval: minutes)

      assert_equal %w[0826 0827], result.days.map(&:key), "#{minutes}-minute periods"
      assert_equal 1, result.shifts_on(result.days.last).size
    end
  end

  test "a wide period starting the evening before HQ opens adds no day of its own" do
    open_hq(begins: at(1), ends: at(9))

    result = forecast(interval: 360)

    assert_equal %w[0826], result.days.map(&:key)
    # The period is still there to count, and the day's chart draws it.
    assert_equal at(23, day: 25), result.periods.first.begins
  end

  # A shift with its end typed a year late stretches HQ's hours past a year,
  # which six-hour periods are wide enough to hold. Each day still finds its
  # own periods, however the dates repeat.
  test "a report running over a year still draws each day's traffic" do
    open_hq(begins: at(6), ends: at(18))
    create_slot(@runner, begins: at(6), ends: at(6) + 1.year)
    sign_up(@other, create_slot(@dirt, begins: at(9), ends: at(13)))

    result = forecast(interval: 360)

    assert_equal 1, result.periods_on(result.days.first).sum(&:checkin)
  end

  # Six-hour periods start at 23:00 here, so one is half one night and half the
  # next morning, and both days' charts draw it.
  test "a wide period starting the evening before reaches into the next day's chart" do
    open_hq(begins: at(20), ends: at(10, day: 27))

    result = forecast(interval: 360)

    assert_equal [at(23), at(5, day: 27)], result.periods_on(result.days.last).map(&:begins)
  end

  # --- Burns ---------------------------------------------------------------

  test "burns starting together are one group, named for all of them" do
    open_hq(begins: at(6), ends: at(23), people: [@ranger])
    sign_up(@ranger, create_slot(@burn, begins: at(20), ends: at(22), description: "Man Burn"))
    sign_up(@other, create_slot(@burn, begins: at(20), ends: at(22), description: "Man Burn Eve"))

    burns = HqForecastReport.burn_perimeters(year: YEAR, interval: 60)

    assert_equal 1, burns.size
    assert_equal "Man Burn / Man Burn Eve — Mon Aug 26", burns.first.title
    assert_equal 2, burns.first.periods.first.checkin
  end

  test "burns starting at different times are separate groups" do
    open_hq(begins: at(6), ends: at(23))
    create_slot(@burn, begins: at(20), ends: at(22), description: "Man Burn")
    create_slot(@burn, begins: at(21), ends: at(23), description: "Temple")

    assert_equal 2, HqForecastReport.burn_perimeters(year: YEAR, interval: 60).size
  end

  test "a burn row carries the HQ staffing of its own period" do
    open_hq(begins: at(6), ends: at(23), position: @lead, people: [@ranger])
    sign_up(@other, create_slot(@burn, begins: at(20), ends: at(22), description: "Man Burn"))

    period = HqForecastReport.burn_perimeters(year: YEAR, interval: 60).first.periods.first

    assert_equal at(20), period.begins
    assert_equal 1, period.count_for(:leads)
    assert_not_predicate period, :unstaffed?
  end

  # A burn running after HQ shuts is not an uncovered window, it is a closed
  # one, so it carries no warning.
  test "a burn period outside HQ hours is not flagged as unstaffed" do
    open_hq(begins: at(6), ends: at(12), people: [@ranger])
    sign_up(@other, create_slot(@burn, begins: at(20), ends: at(22), description: "Man Burn"))

    period = HqForecastReport.burn_perimeters(year: YEAR, interval: 60).first.periods.first

    assert_not_predicate period, :unstaffed?
  end

  # A desk with nothing scheduled while the burn runs is not a column of
  # noughts; one with a shift is, sign-ups or not.
  test "a burn names only the desks with a shift in its periods" do
    open_hq(begins: at(6), ends: at(23), position: @lead, people: [@ranger])
    create_slot(@runner, begins: at(6), ends: at(8))
    create_slot(@window, begins: at(21), ends: at(23))
    sign_up(@other, create_slot(@burn, begins: at(20), ends: at(22), description: "Man Burn"))

    burn = HqForecastReport.burn_perimeters(year: YEAR, interval: 60).sole

    assert_equal ["HQ Lead", "HQ Window"], burn.desks.map(&:title)
  end

  # Pre-event HQ shifts are HQ's own, so they open the report's hours rather
  # than sending anyone to the window.
  test "pre-event HQ shifts set the hours and are traffic for no one" do
    open_hq(begins: at(6), ends: at(12))
    sign_up(@ranger, create_slot(@pre_event_window, begins: at(6, day: 25), ends: at(14, day: 25)))

    result = forecast

    assert_equal at(6, day: 25), result.periods.first.begins
    assert_equal 0, result.checkin_total
  end

  test "no burn shifts means no burn groups" do
    open_hq

    assert_empty HqForecastReport.burn_perimeters(year: YEAR, interval: 60)
  end

  # --- Who is signed up for a period --------------------------------------

  test "a shift overlapping the period at all puts its people in the list" do
    slot = create_slot(@window, begins: at(6), ends: at(14))
    sign_up(@ranger, slot)

    people = HqForecastReport.people_in_period(position_id: Position::HQ_WINDOW,
                                               period: at(9), interval: 60)

    assert_equal [@ranger.id], people.map(&:person_id)
  end

  test "a shift ending exactly when the period opens is not in it" do
    sign_up(@ranger, create_slot(@window, begins: at(6), ends: at(9)))

    assert_empty HqForecastReport.people_in_period(position_id: Position::HQ_WINDOW,
                                                   period: at(9), interval: 60)
  end

  test "a shift starting exactly when the period closes is not in it" do
    sign_up(@ranger, create_slot(@window, begins: at(10), ends: at(14)))

    assert_empty HqForecastReport.people_in_period(position_id: Position::HQ_WINDOW,
                                                   period: at(9), interval: 60)
  end

  test "the list only holds the desk that was asked for" do
    sign_up(@ranger, create_slot(@window, begins: at(6), ends: at(14)))
    sign_up(@other, create_slot(@lead, begins: at(6), ends: at(14)))

    people = HqForecastReport.people_in_period(position_id: Position::HQ_LEAD,
                                               period: at(9), interval: 60)

    assert_equal [@other.id], people.map(&:person_id)
  end

  # --- Who is signed up for a shift ----------------------------------------

  # The list has to agree with the count on the bar that opens it, so a shift
  # overlapping it at the same desk stays out.
  test "a shift's list holds its own people and no one else's" do
    slot = open_hq(begins: at(6), ends: at(14), people: [@ranger])
    open_hq(begins: at(10), ends: at(18), people: [@other])

    shift, people = HqForecastReport.people_on_shift(slot.id)

    assert_equal ["HQ Window", at(6), at(14), 1], [shift.desk.title, shift.begins, shift.ends, shift.signups]
    assert_equal [@ranger.id], people.map(&:person_id)
  end

  # The dialog is HQ's own roster, not a way to look up any shift of the event.
  test "a shift at any other desk has no list" do
    dirt = create_slot(@dirt, begins: at(6), ends: at(14))
    sign_up(@ranger, dirt)

    assert_nil HqForecastReport.people_on_shift(dirt.id)
  end

  test "a shift that is not live, or does not exist, has no list" do
    dead = open_hq(people: [@ranger])
    dead.update_columns(active: false)

    assert_nil HqForecastReport.people_on_shift(dead.id)
    assert_nil HqForecastReport.people_on_shift(nil)
  end

  # --- The period width ----------------------------------------------------

  # Pins where the wide widths actually cut the day. They run on a fixed grid
  # from the epoch rather than from midnight, so they start on whatever hour
  # the offset lands them on -- surprising, and long-standing, so it is written
  # down here rather than left to be rediscovered.
  test "the wide period widths cut on a fixed grid, not from midnight" do
    open_hq(begins: at(0), ends: at(23, 59))

    %w[180 360].each do |minutes|
      starts = forecast(interval: minutes.to_i).periods.map(&:begins)
      step = minutes.to_i * 60

      assert starts.each_cons(2).all? { |a, b| b - a == step },
             "#{minutes}-minute periods should be evenly spaced"
      assert starts.all? { |time| (time.to_i % step).zero? },
             "#{minutes}-minute periods should land on the epoch grid"
    end
  end

  test "a period width the report does not offer falls back to the default" do
    assert_equal 60, HqForecastReport.normalize_interval(7)
    assert_equal 60, HqForecastReport.normalize_interval(nil)
    assert_equal 60, HqForecastReport.normalize_interval("nonsense")
    assert_equal 15, HqForecastReport.normalize_interval("15")
  end

  # --- The spreadsheet -----------------------------------------------------

  test "the export names every period, whatever the page is showing" do
    open_hq(begins: at(6), ends: at(9), people: [@ranger])
    sign_up(@other, create_slot(@dirt, begins: at(7), ends: at(8)))

    rows = HqForecastReport.csv_rows(forecast)

    # The pre-event desks lead the staffing columns.
    assert_equal ["Time (1 hour interval)", "Check In", "Check Out", "HQ Lead - Pre-event",
                  "HQ Window - Pre-event", "HQ Lead", "HQ Short", "HQ Window", "HQ Runner"], rows.first
    assert_equal 4, rows.size
    assert_equal "#{YEAR}-08-26 07:00", rows[2].first
    assert_equal 1, rows[2][1]
    # Each count sits under its own heading: the one window volunteer, and no
    # one at the pre-event window in front of it.
    assert_equal 1, rows[2][rows.first.index("HQ Window")]
    assert_equal 0, rows[2][rows.first.index("HQ Window - Pre-event")]
  end

  test "a pre-event desk's count lands in its own column" do
    open_hq(begins: at(6), ends: at(9), position: @pre_event_window, people: [@ranger])

    rows = HqForecastReport.csv_rows(forecast)

    assert_equal [1, 0], rows[1].values_at(rows.first.index("HQ Window - Pre-event"), rows.first.index("HQ Window"))
  end
end
