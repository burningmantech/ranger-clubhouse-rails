# frozen_string_literal: true

module Scheduling
  # The credit rate one position's shifts earn at every moment of a year, read
  # off its PositionCredit records. Credits layer: PositionCredit.credits_for
  # adds every credit covering an instant, so the effective rate is a step
  # function whose steps fall on the credits' start and end times.
  #
  # Backs the stacked chart on the position credits timeline page.
  class CreditTimeline
    # One credit description: a legend entry and a colour slot, 1-based in
    # stacking order. The stylesheet has eight colours; later slots share a grey.
    Series = Struct.new(:description, :slot)
    Layer = Struct.new(:series, :rate)
    # One step of the combined rate: the credits active between two boundaries.
    Segment = Struct.new(:starts_at, :ends_at, :layers) do
      def total = layers.sum(&:rate)

      def minutes = ((ends_at - starts_at) / 60).round
    end

    # Tick spacings tried in order until the axis has at most six intervals.
    TICK_STEPS = [0.25, 0.5, 1, 2, 5, 10, 20, 50, 100].freeze

    attr_reader :credits, :starts_at, :ends_at, :series, :segments

    def initialize(credits)
      @credits = credits
      times = credits.flat_map { |credit| [credit.start_time, credit.end_time] }
      @starts_at = times.min.beginning_of_day
      @ends_at = times.max.beginning_of_day
      # Whole days, never an empty span: a credit ending at midnight ends the
      # span there, a later end needs the next day, and a zero-length credit
      # at midnight still gets one day to draw.
      @ends_at += 1.day if @ends_at < times.max || @ends_at == @starts_at
      @series = build_series
      @segments = build_segments
    end

    def days = @days ||= (starts_at.to_date...ends_at.to_date).to_a

    def span_minutes = ((ends_at - starts_at) / 60).round

    # The tallest stack of drawn rates. A negative credit lowers a step's
    # total but is not drawn, so it must not shrink the axis.
    def peak
      @peak ||= segments.map { |segment| segment.layers.sum { |layer| [layer.rate, 0].max } }.max
    end

    def y_step = TICK_STEPS.find { |step| peak / step <= 6 } || TICK_STEPS.last

    def y_max = [(peak / y_step).ceil, 1].max * y_step

    def y_ticks = (0..(y_max / y_step).round).map { |i| i * y_step }

    private

    def duration(credit) = ((credit.end_timestamp - credit.start_timestamp) / 60.0).round

    # Descriptions with the longest single credit first: a season-long base
    # rate takes slot 1 and sits at the bottom of the stack, while a daily
    # grave bump rides on top. Ties break on total coverage, then name.
    def build_series
      groups = credits.group_by(&:description).map { |description, group|
        durations = group.map { |credit| duration(credit) }
        [description, durations.max, durations.sum]
      }
      groups.sort_by { |description, longest, total| [-longest, -total, description] }
            .map.with_index(1) { |(description, *), slot| Series.new(description, slot) }
    end

    # Every credit boundary splits the span; between two boundaries the set of
    # active credits is constant. Layers follow series order.
    def build_segments
      bounds = (credits.flat_map { |credit| [credit.start_time, credit.end_time] } + [starts_at, ends_at])
               .uniq(&:to_i).sort
      bounds.each_cons(2).map { |from, to|
        active = credits.select { |credit| credit.start_timestamp <= from.to_i && credit.end_timestamp >= to.to_i }
                        .group_by(&:description)
        layers = series.filter_map { |entry|
          group = active[entry.description]
          Layer.new(entry, group.sum(&:credits_per_hour)) if group
        }
        Segment.new(from, to, layers)
      }
    end
  end
end
