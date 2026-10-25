# frozen_string_literal: true

require "test_helper"

# How a span is read. The counting is covered by the two reports that use it.
class EventYearSpanTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  YEAR = 2031

  setup do
    Current.reset
    travel_to Time.zone.local(YEAR, 8, 26, 12, 0, 0)
  end

  teardown do
    travel_back
    Current.reset
  end

  test "the menus offer every event year from the first to this one, newest first" do
    options = EventYearSpan.year_options

    assert_equal YEAR, options.first
    assert_equal EventYearSpan::FIRST_YEAR, options.last
    assert_empty options & [2020, 2021]
  end

  test "spans are held to the years the menus offer" do
    assert_equal [YEAR - 3, YEAR], EventYearSpan.span(YEAR, YEAR - 3), "turned around"
    assert_equal [2022, YEAR], EventYearSpan.span(2021, nil), "nearest event year; missing is this year"
    assert_equal [2010, YEAR], EventYearSpan.span(1999, YEAR + 5), "out of range is the nearer end"
    # Not turned into 2015 to this year, a different span from the one asked for.
    assert_equal [2010, 2015], EventYearSpan.span(2009, 2015)
    assert_equal [YEAR - 4, YEAR], EventYearSpan.span(["x"], { "a" => "b" }, default_start: YEAR - 4),
                 "unreadable is the default"
  end

  test "the last years count events, not years" do
    assert_equal [2023, 2024, 2025], EventYearSpan.last_years(3, through: 2025)
    assert_equal [2018, 2019, 2022], EventYearSpan.last_years(3, through: 2022), "across the gap"
    assert_equal [2017, 2018, 2019], EventYearSpan.last_years(3, through: 2021), "from inside it"
  end

  test "a run of years skips some only when it crosses the two with no event" do
    assert EventYearSpan.skips_years?(EventYearSpan.last_years(5, through: 2025))
    assert EventYearSpan.skips_years?(EventYearSpan.years(2019, 2022))
    assert_not EventYearSpan.skips_years?(EventYearSpan.last_years(5, through: 2026))
    assert_not EventYearSpan.skips_years?([2019]), "one year has no middle"
  end
end
