# frozen_string_literal: true

require "test_helper"

class Scheduling::CreditTimelineTest < ActiveSupport::TestCase
  def credit(description, rate, from, to)
    PositionCredit.new(description:, credits_per_hour: rate,
                       start_time: Time.zone.parse(from), end_time: Time.zone.parse(to))
  end

  def timeline(*credits) = Scheduling::CreditTimeline.new(credits)

  setup do
    @timeline = timeline(credit("Grave", 0.25, "2026-09-05 00:00", "2026-09-05 06:00"),
                         credit("Base Rate", 1.0, "2026-09-04 06:00", "2026-09-06 12:00"),
                         credit("Weekend", 0.5, "2026-09-05 00:00", "2026-09-07 00:00"))
    @step = @timeline.segments.find { |segment| segment.starts_at == Time.zone.parse("2026-09-05 00:00") }
  end

  test "spans whole days and orders series by their longest credit" do
    assert_equal [Date.new(2026, 9, 4), Date.new(2026, 9, 5), Date.new(2026, 9, 6)], @timeline.days
    assert_equal ["Base Rate", "Weekend", "Grave"], @timeline.series.map(&:description)
    assert_equal [1, 2, 3], @timeline.series.map(&:slot)
  end

  test "segments sum every credit covering the step" do
    assert_equal Time.zone.parse("2026-09-05 06:00"), @step.ends_at
    assert_equal 6 * 60, @step.minutes
    assert_in_delta 1.75, @step.total
    assert_equal ["Base Rate", "Weekend", "Grave"], @step.layers.map { |layer| layer.series.description }
    assert_equal 0, @timeline.segments.first.total # midnight to 06:00 on the 4th, before any credit
    assert_in_delta 1.75, @timeline.peak
    assert_equal [0, 0.5, 1.0, 1.5, 2.0], @timeline.y_ticks
  end

  test "a step's rate is what the model's credit math pays" do
    paid = PositionCredit.credits_for(@timeline.credits, @step.starts_at.to_i, @step.ends_at.to_i)

    assert_in_delta paid, @step.total * (@step.minutes / 60.0)
  end

  test "degenerate credits still draw" do
    zero_length = timeline(credit("Stub", 1.0, "2026-09-05 00:00", "2026-09-05 00:00"))
    assert_equal [Date.new(2026, 9, 5)], zero_length.days
    assert_equal [0, 0.25], zero_length.y_ticks

    penalised = timeline(credit("Base", 1.0, "2026-09-05 00:00", "2026-09-05 06:00"),
                         credit("Penalty", -0.5, "2026-09-05 00:00", "2026-09-05 06:00"))
    assert_in_delta 0.5, penalised.segments.first.total
    assert_in_delta 1.0, penalised.peak # the drawn stack, not the net total

    inverted = timeline(credit("Base", 1.0, "2026-09-04 06:00", "2026-09-06 12:00"),
                        credit("Bad", 1.0, "2026-09-08 00:00", "2026-09-07 00:00"))
    assert_equal Date.new(2026, 9, 7), inverted.days.last # the axis covers every boundary

    assert_equal 7, timeline(credit("Big", 30.0, "2026-09-05 00:00", "2026-09-05 06:00")).y_ticks.size
  end
end
