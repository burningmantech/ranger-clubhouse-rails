# frozen_string_literal: true

require "test_helper"

# Blocker labels have to say by how much a check failed, not just which check:
# an HQ lead deciding whether to force a start, and whoever reviews it after,
# are both judging the size of the miss.
class Person::TimesheetsHelperTest < ActionView::TestCase
  include Person::TimesheetsHelper
  include DateTimeHelper

  test "a too-early check-in says how early, against the shift start and the window" do
    label = timesheet_blocker_label(
      blocker: Timesheet::BLOCKED_TOO_EARLY,
      distance: 105,
      cutoff: 30,
      allowed_in: 75,
      slot: { id: 1, begins: "2031-08-26 06:45:00", description: "Morning" }
    )

    assert_equal "Attempted to sign in too early — 1 hour 45 mins before the 06:45 start; " \
                 "check-in opens 30 minutes before the start", label
  end

  test "a too-late check-in says how late, against the shift start and the window" do
    label = timesheet_blocker_label(
      "blocker" => Timesheet::BLOCKED_TOO_LATE,
      "distance" => 130,
      "cutoff" => 15,
      "slot" => { "begins" => "2031-08-26 20:00:00" }
    )

    assert_equal "Attempted to sign in too late — 2 hours 10 mins after the 20:00 start; " \
                 "check-in closes 15 minutes after the start", label
  end

  # hour_minute_words has no day component: a real 2025 blocker (distance
  # 40237) rendered as "670 hours 37 mins", and the slot it names is nowhere
  # near the shift start printed beside it.
  test "a check-in blocked more than a day out is said in days, and dates its slot" do
    label = timesheet_blocker_label("blocker" => Timesheet::BLOCKED_TOO_EARLY,
                                    "distance" => 40_237, "cutoff" => 30,
                                    "slot" => { "begins" => "2025-09-24 16:00:00" })

    assert_includes label, "27 days 22 hours before the Sep 24 16:00 start"
    assert_not_includes label, "670 hours"
  end

  test "a check-in blocked inside a day keeps the bare time and minutes" do
    label = timesheet_blocker_label("blocker" => Timesheet::BLOCKED_TOO_EARLY,
                                    "distance" => 1439,
                                    "slot" => { "begins" => "2025-09-24 16:00:00" })

    assert_includes label, "23 hours 59 mins before the 16:00 start"
  end

  # slot.begins is stored as local wall-clock. Parsing it into a zone shifts the
  # digits, and the reader is checking them against the printed schedule.
  test "the shift start is read as wall-clock, not shifted into a timezone" do
    label = timesheet_blocker_label("blocker" => Timesheet::BLOCKED_TOO_LATE,
                                    "slot" => { "begins" => "2031-08-26 23:30:00" })

    assert_includes label, "shift starts at 23:30"
  end

  test "burn perimeter experience says what is required against what is on record" do
    label = timesheet_blocker_label("blocker" => Timesheet::BLOCKED_NO_BURN_PERIMETER_EXP,
                                    "within_years" => 5,
                                    "last_worked" => { "title" => "Burn Perimeter", "year" => 2024 })

    assert_equal "No recent burn perimeter experience — needs experience within 5 years; " \
                 "last was Burn Perimeter in 2024", label
  end

  test "burn perimeter with a recorded blank says none is on record" do
    label = timesheet_blocker_label("blocker" => Timesheet::BLOCKED_NO_BURN_PERIMETER_EXP,
                                    "within_years" => 5, "last_worked" => nil)

    assert_includes label, "none on record"
  end

  # The pre-2025 conversion writes within_years and nothing else. Claiming
  # "none on record" there would be asserting a fact the log never held.
  test "a pre-2025 burn perimeter blocker claims nothing about past experience" do
    label = timesheet_blocker_label("blocker" => Timesheet::BLOCKED_NO_BURN_PERIMETER_EXP,
                                    "within_years" => 5)

    assert_equal "No recent burn perimeter experience — needs experience within 5 years", label
  end

  test "a blocker with no recorded detail keeps its bare label" do
    assert_equal "Sandman Affidavit not signed",
                 timesheet_blocker_label("blocker" => Timesheet::BLOCKED_UNSIGNED_SANDMAN_AFFIDAVIT)
  end

  test "an untrained blocker still names the training it wants" do
    assert_equal "Has not completed training - In-Person Training",
                 timesheet_blocker_label(blocker: Timesheet::BLOCKED_NOT_TRAINED,
                                         position: { id: Position::TRAINING,
                                                     title: "In-Person Training" })
  end
end
