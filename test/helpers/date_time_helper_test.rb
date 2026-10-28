# frozen_string_literal: true

require "test_helper"

class DateTimeHelperTest < ActionView::TestCase
  test "an admin log's time reads to the second, in the app zone" do
    assert_equal "2026-04-09 08:30:15", log_time_format(Time.zone.local(2026, 4, 9, 8, 30, 15))
    # Phoenix keeps no daylight time: 15:30 UTC is 08:30 there all year.
    assert_equal "2026-04-09 08:30:15", log_time_format(Time.utc(2026, 4, 9, 15, 30, 15))
    assert_equal "", log_time_format(nil)
  end

  test "tz labels the time without converting the wall clock" do
    time = Time.zone.local(2026, 1, 15, 6, 15) # app zone: America/Phoenix

    html = datetime_format(time, tz: "America/New_York", tz_abbr: "ET")

    assert_includes html, "06:15 (ET)" # not shifted to 08:15
  end

  test "string times parse in the given zone" do
    html = datetime_format("2026-01-15 06:15:00", tz: "America/New_York", tz_abbr: "ET")

    assert_includes html, "06:15 (ET)"
  end

  test "the browser's tooltip gets the instant, not the wall clock" do
    html = datetime_format("2026-01-15 06:15:00", tz: "America/New_York", tz_abbr: "ET")

    assert_includes html, %(data-local-time-target="time")
    assert_includes html, %(data-utc="2026-01-15T11:15:00Z")
  end

  # November, when Pacific has left daylight time and Phoenix never keeps it:
  # stamped as a Pacific wall clock, a timestamp hovered an hour late.
  test "a timestamp keeps the app's clock and its instant, winter included" do
    september = datetime_format(Time.zone.local(2026, 9, 15, 14, 30))
    november = datetime_format(Time.zone.local(2026, 11, 5, 14, 30))

    assert_includes september, %(title="Tue Sep 15, 2026 @ 14:30 (MST)")
    assert_includes september, %(data-utc="2026-09-15T21:30:00Z")
    assert_includes november, ">Thu Nov 5 @ 14:30<"
    assert_includes november, %(title="Thu Nov 5, 2026 @ 14:30 (MST)")
    assert_includes november, %(data-utc="2026-11-05T21:30:00Z")
  end

  test "a Pacific timestamp moves to Pacific's clock and keeps its instant" do
    html = pacific_datetime_format(Time.zone.local(2026, 11, 5, 14, 30))

    assert_includes html, ">Thu Nov 5, 2026 @ 13:30 (PT)<" # not 14:30, the Phoenix digits
    assert_includes html, %(data-utc="2026-11-05T21:30:00Z")
    assert_equal "", pacific_datetime_format(nil)
  end

  # The second 01:30 of the night Pacific falls back. Stamping those digits
  # again, as datetime_format's tz: would, lands on the first one.
  test "a zoned timestamp in the repeated hour keeps its instant" do
    html = zoned_datetime_format(Time.utc(2026, 11, 1, 9, 30), tz: "America/Los_Angeles", tz_abbr: "PT")

    assert_includes html, ">Sun Nov 1, 2026 @ 01:30 (PT)<"
    assert_includes html, %(data-utc="2026-11-01T09:30:00Z")
  end

  test "a short date and time fits a chip, and nothing prints nothing" do
    assert_equal "Wed 9/2 05:07", short_datetime_format(Time.zone.local(2026, 9, 2, 5, 7))
    assert_equal "", short_datetime_format(nil)
  end
end
