# frozen_string_literal: true

# Every method here is prefixed. Rails helper names share one namespace across
# the whole app, so a bare `period_label` or `chart` would answer for every
# other page too.
module Scheduling::HqForecastHelper
  # The hour a row stands for. The burn's name and night head the section, so
  # the row only has to say the time.
  def hq_forecast_period_label(period) = period.begins.strftime("%H:%M")

  # Rows needing attention are tinted and flagged, never tinted alone.
  def hq_forecast_row_state(period)
    :warning if period.unstaffed?
  end

  def hq_forecast_period_cell(period)
    return hq_forecast_period_label(period) unless period.unstaffed?

    # The icon is hidden from readers, so the row says it in words too --
    # otherwise the one thing the page is for is the one thing not announced.
    safe_join([fa_icon("triangle-exclamation", :solid, class: "icon-warning me-1"),
               hq_forecast_period_label(period),
               tag.span(HQ_FORECAST_GAP_WORDS, class: "sr-only")], " ")
  end

  # A staffing count opens the list of who it stands for. Nought opens nothing
  # -- there is no one behind it to show.
  def hq_forecast_staffing_cell(period, desk, interval)
    count = period.count_for(desk.key)
    return tag.span("0", class: "text-stone-subtle") if count.zero?

    link_to count, scheduling_hq_forecast_people_path(position_id: desk.position_id,
                                                      period: period.begins.iso8601,
                                                      interval:),
            class: LinkHelper::TABLE_LINK_CLASSES,
            data: { turbo_frame: "modal" },
            aria: { label: "#{count} at #{desk.title}, #{hq_forecast_period_label(period)}" }
  end

  # How many periods of a day have no one answering the window, said in the
  # day's own heading so a reader scrolling past knows to stop. The words carry
  # it, not the colour. Counted from what the day's chart draws, so the heading
  # and the hatching beneath it agree.
  def hq_forecast_day_badge(report, day)
    count = report.unstaffed_on(day)
    "#{count} unstaffed" if count.positive?
  end

  # The hour a row stands for, said with its date. For anything naming one
  # moment out of the whole report -- the busiest period, say -- the time alone
  # could be any of a dozen days, and the weekday alone any of three weeks.
  def hq_forecast_moment_label(period) = period.begins.strftime(DateTimeHelper::MONTH_DAY_TIME)

  # What a gap is, in the words every mark and row uses for one. A runner is
  # an HQ volunteer, but not one who answers the window.
  HQ_FORECAST_GAP_WORDS = "no lead, short, or window on duty"

  # --- The day's chart ---------------------------------------------------------
  #
  # A Gantt chart of one day: the check-in/out traffic across the top, then a
  # lane for each HQ desk with every shift drawn as a bar over the hours it
  # runs. Plain HTML laid out with utilities here; hq-forecast.css holds the
  # geometry and the hatching. The only inline styles are custom properties
  # carrying the numbers the stylesheet cannot know, the exception AGENTS.md >
  # CSS Rules allows.

  # Every chart runs midnight to midnight, however long HQ is open that day, so
  # the charts down the page share one clock. hq-forecast.css divides by the
  # same number.
  GANTT_DAY_MINUTES = 1440

  # How long a shift has to run for its bar to clear the 36px touch floor with
  # the chart at its narrowest: 40rem, less the 6.5rem of lane names.
  GANTT_TOUCH_MINUTES = 97

  def hq_forecast_gantt(report, day)
    by_desk = report.shifts_on(day).group_by(&:desk)
    desk_lanes = HqForecastReport::DESKS.flat_map do |desk|
      hq_forecast_gantt_rows(by_desk.fetch(desk, [])).map.with_index do |row, index|
        marks = row.map { |shift| hq_forecast_shift_mark(shift, day) }
        hq_forecast_gantt_lane((desk.title if index.zero?), marks, "h-10")
      end
    end
    traffic = hq_forecast_gantt_lane("Check In/Out", hq_forecast_traffic_marks(report, day), "h-12")
    grid = tag.div(safe_join([hq_forecast_gantt_axis, traffic, *desk_lanes]), class: "hq-gantt grid min-w-160")

    # Scrolls sideways inside its own box on a phone, where the chart is wider
    # than the screen, and never up and down. Scrolled to a focused bar, the
    # box stops short of the pinned lane names rather than parking the bar
    # under them. From lg it fits, and tooltips are free to overhang.
    tag.div(class: "hq-gantt-chart", role: "group",
            aria: { label: "#{day.label} HQ shifts and check-in/out traffic" }) do
      safe_join([tag.div(grid, class: "overflow-x-auto overflow-y-hidden scroll-ps-26 lg:overflow-visible"),
                 hq_forecast_gantt_legend])
    end
  end

  # The shift a dialog lists, with its day and its hours.
  def hq_forecast_shift_title(shift)
    "#{shift.desk.title} — #{shift.begins.strftime(DateTimeHelper::MONTH_DAY_TIME)} to " \
      "#{hq_forecast_clock(shift.ends, shift.begins.to_date)}"
  end

  # The way across to the report's other page. Separate pages rather than panes:
  # each asks a different question of the year, and only the one on screen is
  # worth building. The year and the period width follow the reader across.
  #
  # One button naming where it goes, rather than a tab strip: two pages this far
  # apart are two reports, and a tab strip says they are two views of the one
  # thing on screen.
  def hq_forecast_other_page_link(current, year:, interval:)
    label, icon, path =
      if current == :burns
        ["All Shifts", "table-list", scheduling_hq_forecast_path(year:, interval:)]
      else
        ["Burn Perimeters", "fire", scheduling_hq_forecast_burn_perimeters_path(year:, interval:)]
      end

    tag.div(button_link(label, :secondary, path, icon:, icon_type: :solid), class: "mb-4")
  end

  def hq_forecast_day_options(report)
    [["All days", HqForecastReport::ALL_DAYS]] + report.day_options
  end

  # The day is the one way of narrowing the page, so it is the one chip. The
  # interval is not a chip: it says how the report is cut up rather than
  # holding anything back, so removing it would have nowhere to land.
  #
  # The chip's URL is built from the whole filter set, so dropping it keeps the
  # year and the period width the reader is looking at.
  def hq_forecast_filter_chips(report, filters)
    day_label = ->(_key, value) { report.days.find { |day| day.key == value }&.label || value }

    filter_chips(filters.slice(:day), { day: "Day" }, value_label: day_label) do |_rest, key|
      scheduling_hq_forecast_path(filters.except(key))
    end
  end

  def hq_forecast_count(report, days)
    return "Showing #{pluralize(days.size, "day")}" if days.size == report.days.size

    "Showing #{days.size} of #{pluralize(report.days.size, "day")}"
  end

  private

  # One row of the chart: its name in the column pinned while the hours scroll,
  # then its marks on the hours. A desk whose shifts overlap takes more than one
  # row, and only the first is named.
  #
  # The name is lifted over the scrolling marks only while it is pinned. From
  # lg nothing scrolls under it, and a raised name would sit on top of the
  # tooltips that overhang it.
  def hq_forecast_gantt_lane(label, marks, height)
    safe_join([tag.div(label, class: "sticky left-0 z-10 flex items-center border-t border-base-300 bg-base-100 pe-2 " \
                                     "text-base text-body lg:static lg:z-auto"),
               tag.div(safe_join(marks), class: class_names("hq-gantt-lane relative border-t border-e border-base-300", height))])
  end

  # The hours across the top, each beside the line it names: every third hour,
  # the step grid-cols-8 lays out and the 12.5% hour lines in hq-forecast.css
  # repeat, so the three change together. Hidden from screen readers: every
  # mark says its own times in words.
  def hq_forecast_gantt_axis
    hours = (0...24).step(3).map { |hour| tag.span(format("%02d:00", hour), class: "ps-1") }
    safe_join([tag.div(class: "sticky left-0 z-10 bg-base-100 lg:static lg:z-auto", aria: { hidden: true }),
               tag.div(safe_join(hours), class: "grid grid-cols-8 pb-1 text-sm text-stone-subtle tabular-nums",
                                         aria: { hidden: true })])
  end

  # Everyone expected at the window, period by period, as bars as tall as their
  # share of the day's busiest period -- so a quiet day still shows its own
  # shape. A period with no one on duty to meet them is hatched down its whole
  # column: a quiet gap has almost no bar to mark, and it is still a gap.
  def hq_forecast_traffic_marks(report, day)
    periods = report.periods_on(day)
    peak = periods.map(&:demand).max.to_i
    width = report.interval.minutes

    periods.map do |period|
      share = peak.zero? ? 0 : (period.demand * 100.0 / peak).round
      label = hq_forecast_traffic_label(period, day)
      hq_forecast_gantt_mark(period.begins, period.begins + width, day, tip: label, tip_below: true,
                             share: [share, 2].max, role: "img", aria: { label: },
                             class: class_names("flex items-end", "hq-gantt-gap": period.unstaffed?)) do
        tag.span(class: "hq-gantt-fill mx-px flex-1 rounded-t-sm bg-base-content/50")
      end
    end
  end

  # Everything a traffic bar shows, for a reader who cannot see it.
  def hq_forecast_traffic_label(period, day)
    parts = ["#{hq_forecast_clock(period.begins, day.starts.to_date)}:",
             "#{period.checkin} checking in,",
             "#{period.checkout} checking out"]
    parts << "— #{HQ_FORECAST_GAP_WORDS}" if period.unstaffed?
    parts.join(" ")
  end

  # A desk's shifts, packed onto as few rows as hold them without one bar drawn
  # over another. Shifts at a desk usually follow on from one another, so this
  # is nearly always one row. A desk with nothing scheduled that day gets none:
  # the pre-event desks would otherwise run empty down every day of the event.
  def hq_forecast_gantt_rows(shifts)
    shifts.each_with_object([]) do |shift, packed|
      row = packed.find { |candidate| candidate.last.ends <= shift.begins }
      row ? row << shift : packed << [shift]
    end
  end

  # One shift: a bar over the hours it runs, reading how many of its places are
  # taken. The bar opens the list of who is signed up. One with no one on it
  # opens nothing -- there is no one to show -- and is hatched instead.
  #
  # The link fills the lane's height, over the 36px floor, and reaches past a
  # bar too short to clear it (hq-forecast.css); a short bar is lifted above
  # its neighbours so that reach is its own. A bar cut off at midnight is
  # squared off on that side: the shift carries on in the next or the last
  # day's chart.
  def hq_forecast_shift_mark(shift, day)
    # A shift that takes as many as turn up has no limit to count against.
    count = shift.max.positive? ? "#{shift.signups}/#{shift.max}" : shift.signups.to_s
    label = hq_forecast_shift_label(shift, count, day)
    text = tag.span(count, class: class_names("hq-gantt-bar-text px-1", "hq-gantt-bar-text-long": count.size > 3))
    bar = tag.span(text, class: class_names("hq-gantt-bar absolute inset-x-px inset-y-2 flex items-center rounded-sm text-sm tabular-nums",
                                            "@container",
                                            shift.signups.zero? ? "hq-gantt-vacant" : "bg-base-content/80 text-base-100",
                                            "rounded-s-none": shift.begins < day.starts,
                                            "rounded-e-none": shift.ends > day.ends))
    face = if shift.signups.zero?
             tag.span(bar, class: "block size-full", role: "img", aria: { label: })
           else
             link_to(bar, scheduling_hq_forecast_shift_path(shift.id), class: "hq-gantt-hit block size-full",
                                                                      data: { turbo_frame: "modal" }, aria: { label: })
           end

    hq_forecast_gantt_mark(shift.begins, shift.ends, day, tip: label, lift_if_short: shift.signups.positive?) { face }
  end

  # Everything a shift's bar shows, in words, and the name its link goes by. It
  # leads with the count the bar shows, so a reader who can see "1/20" can say
  # it to reach the link.
  def hq_forecast_shift_label(shift, count, day)
    date = day.starts.to_date
    "#{count} signed up, #{shift.desk.title}, " \
      "#{hq_forecast_clock(shift.begins, date)} to #{hq_forecast_clock(shift.ends, date)}"
  end

  # A mark placed on the day, the one place the chart's numbers are written:
  # where it starts and how long it runs, in minutes from midnight cut to the
  # day, and a traffic bar's height.
  #
  # A tooltip is at most 14rem wide (hq-forecast.css), under half the chart at
  # its narrowest, so a mark centred near either end opens its tooltip to the
  # side, where it fits; elsewhere it opens above -- or below, in the top lane,
  # which has nothing above it but the hours in a box that scrolls. The words
  # ride in a hidden child rather than data-tip: a tooltip drawn from the
  # attribute is read out beside the mark's own label.
  def hq_forecast_gantt_mark(from, to, day, tip:, tip_below: false, lift_if_short: false, share: nil, **options)
    start = hq_forecast_minutes(from, day).clamp(0, GANTT_DAY_MINUTES)
    finish = hq_forecast_minutes(to, day).clamp(0, GANTT_DAY_MINUTES)
    middle = (start + finish) / 2
    side = if middle < GANTT_DAY_MINUTES * 0.22 then "tooltip-right"
           elsif middle > GANTT_DAY_MINUTES * 0.78 then "tooltip-left"
           elsif tip_below then "tooltip-bottom"
           end
    style = "--start: #{start}; --span: #{finish - start}"
    style += "; --share: #{share}" if share

    tag.div(class: class_names("hq-gantt-mark tooltip absolute inset-y-0", side, options.delete(:class),
                               "z-1": lift_if_short && finish - start < GANTT_TOUCH_MINUTES),
            style:, **options) do
      safe_join([tag.span(tip, class: "tooltip-content", aria: { hidden: true }), yield])
    end
  end

  def hq_forecast_minutes(time, day) = ((time - day.starts) / 60).round

  # A time on the chart's own date says only the hour; one the day before or
  # after says which, or a shift running past midnight reads as ending before
  # it began. Further off than that -- a shift with its end typed a week or a
  # month out -- the weekday would read as this week's, so it says the date.
  def hq_forecast_clock(time, date)
    format = case (time.to_date - date).abs
             when 0 then DateTimeHelper::HOUR_MINS
             when 1 then DateTimeHelper::HOUR_MIN_DAY
             else DateTimeHelper::MONTH_DAY_TIME
             end
    time.strftime(format)
  end

  # What each kind of mark means. The hatching says it as well as the colour,
  # so no difference rests on colour alone.
  def hq_forecast_gantt_legend
    tag.div(class: "flex flex-wrap items-center gap-x-4 gap-y-1 pt-2 text-sm text-stone-muted") do
      safe_join([hq_forecast_legend_key("bg-base-content/80", "Signed up"),
                 hq_forecast_legend_key("hq-gantt-vacant", "No one signed up"),
                 hq_forecast_legend_key("bg-base-content/50", "Checking in or out"),
                 hq_forecast_legend_key("hq-gantt-gap", HQ_FORECAST_GAP_WORDS.upcase_first)])
    end
  end

  # The label belongs inside the key beside its swatch. Left outside, the row's
  # own spacing pushes it as far from its swatch as from the other entry.
  def hq_forecast_legend_key(swatch_class, label)
    tag.span(class: "inline-flex-center-gap-2") do
      safe_join([tag.span(class: class_names("hq-gantt-swatch inline-block size-3 rounded-xs", swatch_class)), label])
    end
  end
end
