# frozen_string_literal: true

require "test_helper"

# calculate_item on its own: the initializer reads timesheets, sign-ups and settings,
# none of which is under test here.
class TicketsAndProvisionsProgressTest < ActiveSupport::TestCase
  HOURS = TicketsAndProvisionsProgress::MEASURE_HOURS
  CREDITS = TicketsAndProvisionsProgress::MEASURE_CREDITS

  test "the percentage rounds down, so a row short of its threshold never reads 100" do
    short = item(215_100, 215_100, 60, HOURS) # 59 hr 45 min of 60 hr
    assert_not short.has_earned
    assert_equal 99, short.percentage

    assert_equal 100, item(216_000, 216_000, 60, HOURS).percentage
    assert_equal 99, item(18.92, 18.92, 19.0, CREDITS).percentage
  end

  test "the sign-ups figure is the difference of the totals as printed, so the parts add up" do
    # 10:30:50 on duty and a shift under way bringing the total to 13:51:05
    hours = item(37_850, 49_865, 60, HOURS)
    assert_equal "10 hours and 30 minutes", hours.value
    assert_equal "13 hours and 51 minutes", hours.expected_total
    assert_equal "3 hours and 21 minutes", hours.scheduled

    credits = item(10.333, 12.667, 38.0, CREDITS)
    assert_equal "10.33 credits", credits.value
    assert_equal "12.67 credits", credits.expected_total
    assert_equal "2.34 credits", credits.scheduled

    assert_equal "0 minutes", item(18_000, 18_000, 60, HOURS).scheduled
  end

  private

  def item(value, expected_total, threshold, measure)
    progress = TicketsAndProvisionsProgress.allocate
    progress.instance_variable_set(:@items, {})
    progress.calculate_item(:all_eats, value, expected_total, threshold, measure, counter: :all_hours)
    progress.items[:all_eats]
  end
end
