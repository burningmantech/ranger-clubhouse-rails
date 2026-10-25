# frozen_string_literal: true

require "test_helper"

# The two things the helper decides on its own: how the span is said, and
# whether the reader is told the list was cut.
class Timesheets::TopHourEarnersHelperTest < ActionView::TestCase
  include Timesheets::TopHourEarnersHelper

  # Rows only have to be countable here; nothing under test reads one.
  def report_of(shown:, total:, start_year: 2022, end_year: 2026)
    TopHourEarnersReport::Report.new(start_year:, end_year:, limit: 50,
                                     years: (start_year..end_year).to_a,
                                     rows: Array.new(shown) { :row }, total:)
  end

  test "a list the limit cut says how many rangers it left off" do
    assert_equal "Showing 50 of 3,000 people for 2022 to 2026",
                 top_hour_earners_count(report_of(shown: 50, total: 3_000))
  end

  test "a list the limit did not cut is not described as a fraction" do
    assert_equal "Showing 2 people for 2022 to 2026",
                 top_hour_earners_count(report_of(shown: 2, total: 2))
  end

  test "a span of one year is said as that year" do
    assert_equal "Showing 1 person for 2024",
                 top_hour_earners_count(report_of(shown: 1, total: 1,
                                                  start_year: 2024, end_year: 2024))
  end

  test "an empty report says nothing at all" do
    assert_nil top_hour_earners_count(report_of(shown: 0, total: 0))
  end

  # --- the best-year mark ------------------------------------------------

  def row_topping(year)
    TopHourEarnersReport::Row.new(person: person(:active_ranger), top_year: year,
                                  top_duration: 100, by_year: { year => 100 })
  end

  test "the best year is marked by more than its tint" do
    classes = top_hour_earners_year_class(row_topping(2024), 2024)

    assert_includes classes, "bg-primary/10"
    assert_includes classes, "font-semibold",
                   "colour alone cannot carry the mark"
  end

  test "every other year is left unmarked" do
    assert_nil top_hour_earners_year_class(row_topping(2024), 2025)
  end
end
