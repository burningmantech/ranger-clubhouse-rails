# frozen_string_literal: true

module Scheduling::PositionCreditsHelper
  # Credits outlive the position they point at. Deleted positions are named by
  # id so their leftover credits can still be found and cleaned up.
  def credit_position_title(position, position_id)
    position&.title || "Position ##{position_id} (deleted)"
  end

  # One filter_bar chip for the position page's day filter; its URL drops the
  # filter and keeps the year.
  def credit_filter_chips(position_id, year)
    return [] if params[:day].blank?

    [{ label: "Day: #{credit_day_label(params[:day])}",
       url: scheduling_position_credits_position_path(position_id, year:) }]
  end

  # --- Credit timeline chart ---------------------------------------------------

  # Series colour classes as a fixed lookup, so no class name is interpolated.
  # A ninth or later series shares the grey ct-s0.
  SERIES_CLASSES = { 1 => "ct-s1", 2 => "ct-s2", 3 => "ct-s3", 4 => "ct-s4",
                     5 => "ct-s5", 6 => "ct-s6", 7 => "ct-s7", 8 => "ct-s8" }.freeze

  # A stacked step chart of the timeline's combined credit rate: legend, plot
  # and day axis. Marks are plain HTML laid out with utilities; the only inline
  # styles are custom properties carrying the numbers the stylesheet cannot
  # know (minutes, credits per hour, days), the exception AGENTS.md > CSS
  # Rules allows. Hover readouts are daisyUI tooltips, so there is no JavaScript.
  def credit_timeline_chart(timeline)
    tag.div(class: "ct mb-3 overflow-x-clip", style: "--ymax: #{timeline.y_max}") do
      safe_join([credit_series_legend(timeline.series), credit_plot(timeline), credit_day_axis(timeline)])
    end
  end

  def credit_series_class(series) = SERIES_CLASSES.fetch(series.slot, "ct-s0")

  def credit_segment_tip(segment)
    "#{credit_tip_time(segment.starts_at)} to #{credit_tip_time(segment.ends_at)}: " \
      "#{credit_format_short(segment.total)}/hr, #{credit_segment_makeup(segment)}"
  end

  # The credits a step is made of, spelled the same in the tooltip, the rate
  # table and its CSV.
  def credit_segment_makeup(segment)
    segment.layers.map { |layer| "#{layer.series.description} #{credit_format_short(layer.rate)}" }
           .join(", ").presence || "No credit"
  end

  private

  def credit_tip_time(time) = time.strftime(DateTimeHelper::MONTH_DAY_TIME)

  def credit_series_legend(series_list)
    tag.div(class: "flex flex-wrap gap-x-4 gap-y-1 mb-2 text-sm") do
      safe_join(series_list.map { |series|
        tag.span(class: "inline-flex-center-gap-2") do
          safe_join([tag.i(class: class_names("ct-swatch size-3 rounded-xs", credit_series_class(series))),
                     series.description])
        end
      })
    end
  end

  # Y ticks behind the steps; the gutter to the left holds their labels.
  def credit_plot(timeline)
    ticks = timeline.y_ticks.map { |tick|
      tag.div(class: "ct-tick absolute inset-x-0", style: "--y: #{tick}") do
        tag.span(credit_format_short(tick),
                 class: "absolute right-full top-0 -translate-y-1/2 pr-2 text-xs text-stone-subtle tabular-nums")
      end
    }
    steps = tag.div(class: "absolute inset-0 flex items-stretch") do
      safe_join(timeline.segments.map { |segment| credit_step(segment, timeline) })
    end
    tag.div(safe_join(ticks << steps), class: "relative h-56 ml-10")
  end

  # One step: its layers stacked bottom-up. Only positive rates are drawn; a
  # zero or negative credit still counts in the tooltip's total.
  def credit_step(segment, timeline)
    layers = segment.layers.select { |layer| layer.rate.positive? }.map { |layer|
      tag.div(class: class_names("ct-layer", credit_series_class(layer.series)), style: "--h: #{layer.rate}")
    }
    tag.div(safe_join(layers),
            class: class_names("ct-seg tooltip flex flex-col-reverse", credit_tip_side(segment, timeline)),
            style: "--w: #{segment.minutes}", data: { tip: credit_segment_tip(segment) })
  end

  # Tooltips open above their step, centred; near either edge that would run
  # off the chart, so there they open to the side instead.
  def credit_tip_side(segment, timeline)
    from = (segment.starts_at - timeline.starts_at) / 60.0 / timeline.span_minutes
    to = (segment.ends_at - timeline.starts_at) / 60.0 / timeline.span_minutes
    if from < 0.2 then "tooltip-right" elsif to > 0.8 then "tooltip-left" end
  end

  # One equal cell per day, numbered when the cells are wide enough (a month
  # or less; past that only Sundays, in bold), over a month row whose cells
  # carry their day count as --w, the flex weight the stylesheet lays the row
  # out by. A month too short to hold its name goes unlabelled.
  def credit_day_axis(timeline)
    days = timeline.days
    number_every_day = days.size <= 31
    tag.div(class: "ml-10") do
      safe_join([
                  tag.div(class: "flex") do
                    safe_join(days.map { |day|
                      tag.span((day.day if number_every_day || day.sunday?),
                               class: class_names("ct-axis-day flex-1 min-w-0 text-center text-xs leading-5 text-stone-subtle",
                                                  "font-semibold": day.sunday?))
                    })
                  end,
                  tag.div(class: "flex") do
                    safe_join(days.chunk_while { |a, b| a.month == b.month }.map { |month|
                      tag.span((month.first.strftime("%B") if month.size >= 4),
                               class: "ct-axis-month min-w-0 text-center text-xs leading-5 whitespace-nowrap",
                               style: "--w: #{month.size}")
                    })
                  end
                ])
    end
  end

  # Unparsable dates fall back to the raw value so a hand-edited URL still
  # renders a removable chip.
  def credit_day_label(value)
    wday_month_day_format(Date.iso8601(value))
  rescue ArgumentError
    value
  end
end
