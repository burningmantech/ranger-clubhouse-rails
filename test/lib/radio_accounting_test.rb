# frozen_string_literal: true

require "test_helper"

# Unit tests for RadioAccounting, the port of the Ember
# clubhouse/utils/radio-accounting.js (staged in port/utils/radio-accounting.js),
# and the HqTodo vocabulary ported from clubhouse/constants/hq-todo.js.
#
# Inputs are plain structs shaped like PersonAsset rows (row.asset.type /
# row.asset.perm_assign) — no fixtures involved.
class RadioAccountingTest < ActiveSupport::TestCase
  FakeAsset = Struct.new(:type, :perm_assign)
  FakeRow = Struct.new(:asset)

  def radio_row(perm_assign: false)
    FakeRow.new(FakeAsset.new(Asset::TYPE_RADIO, perm_assign))
  end

  def gear_row(perm_assign: false)
    FakeRow.new(FakeAsset.new(Asset::TYPE_GEAR, perm_assign))
  end

  # Build a Result the way the HQ shift page does: shift radios are radios NOT
  # permanently assigned, event radios are the permanently assigned ones.
  def accounting_for(shift: 0, event: 0, max: 0)
    rows = Array.new(shift) { radio_row } + Array.new(event) { radio_row(perm_assign: true) }
    RadioAccounting.accounting(rows, max)
  end

  # --- accounting ---

  test "no checked-out assets yields all-zero accounting" do
    result = RadioAccounting.accounting([], 2)

    assert_equal 0, result.shift_radios
    assert_equal 0, result.event_radios
    assert_equal 0, result.collect_count
    assert_equal 0, result.collect_at_shift_end
    assert_equal 0, result.over_max
    assert_equal 2, result.radio_max
    assert_equal 0, result.radio_count
  end

  test "non-radio assets are ignored" do
    result = RadioAccounting.accounting([gear_row, gear_row(perm_assign: true)], 1)

    assert_equal 0, result.radio_count
    assert_equal 0, result.collect_count
  end

  test "shift radios are all collected now" do
    result = accounting_for(shift: 2, max: 1)

    assert_equal 2, result.shift_radios
    assert_equal 0, result.event_radios
    assert_equal 2, result.collect_count
    assert_equal 0, result.collect_at_shift_end
    assert_equal 0, result.over_max
  end

  test "event radios within the limit are only due back when done rangering" do
    result = accounting_for(event: 2, max: 3)

    assert_equal 0, result.shift_radios
    assert_equal 2, result.event_radios
    assert_equal 0, result.collect_count
    assert_equal 0, result.collect_at_shift_end
    assert_equal 2, result.over_max
  end

  test "event radios above the limit are collected at shift end" do
    result = accounting_for(event: 3, max: 1)

    assert_equal 3, result.event_radios
    assert_equal 2, result.collect_at_shift_end
    assert_equal 2, result.collect_count
    assert_equal 1, result.over_max
  end

  test "shift radios and over-limit event radios add up for collection now" do
    result = accounting_for(shift: 1, event: 3, max: 2)

    assert_equal 1, result.shift_radios
    assert_equal 3, result.event_radios
    assert_equal 1, result.collect_at_shift_end
    assert_equal 2, result.collect_count
    assert_equal 2, result.over_max
    assert_equal 4, result.radio_count
  end

  test "event radios with a zero limit are all collected at shift end" do
    result = accounting_for(event: 2, max: 0)

    assert_equal 2, result.collect_at_shift_end
    assert_equal 2, result.collect_count
    assert_equal 0, result.over_max
  end

  # --- radio_todo: person on duty ---

  test "on duty with radios to collect nags to collect now" do
    todo = RadioAccounting.radio_todo(off_duty: false, no_more_scheduled: false,
                                      accounting: accounting_for(shift: 1, max: 1))

    assert_equal HqTodo::COLLECT_RADIO, todo
  end

  test "on duty collect wins over collect-if-done when both apply" do
    todo = RadioAccounting.radio_todo(off_duty: false, no_more_scheduled: true,
                                      accounting: accounting_for(shift: 1, event: 1, max: 1))

    assert_equal HqTodo::COLLECT_RADIO, todo
  end

  test "on duty with an event radio and no more shifts asks to collect if done" do
    todo = RadioAccounting.radio_todo(off_duty: false, no_more_scheduled: true,
                                      accounting: accounting_for(event: 1, max: 1))

    assert_equal HqTodo::COLLECT_RADIO_IF_DONE, todo
  end

  test "on duty with an event radio and more shifts coming does not nag" do
    todo = RadioAccounting.radio_todo(off_duty: false, no_more_scheduled: false,
                                      accounting: accounting_for(event: 1, max: 1))

    assert_nil todo
  end

  test "on duty with no radios does not nag even when nothing more is scheduled" do
    todo = RadioAccounting.radio_todo(off_duty: false, no_more_scheduled: true,
                                      accounting: accounting_for(max: 1))

    assert_nil todo
  end

  # --- radio_todo: person off duty, event authorized (radio_max > 0) ---

  test "off duty with a shift radio out is nagged to collect before any issue prompt" do
    todo = RadioAccounting.radio_todo(off_duty: true, no_more_scheduled: false,
                                      accounting: accounting_for(shift: 1, max: 2))

    assert_equal HqTodo::COLLECT_RADIO, todo
  end

  test "off duty above the event limit is nagged to collect" do
    todo = RadioAccounting.radio_todo(off_duty: true, no_more_scheduled: false,
                                      accounting: accounting_for(event: 3, max: 2))

    assert_equal HqTodo::COLLECT_RADIO, todo
  end

  test "off duty with an event radio and no more shifts asks to collect if done" do
    todo = RadioAccounting.radio_todo(off_duty: true, no_more_scheduled: true,
                                      accounting: accounting_for(event: 1, max: 2))

    assert_equal HqTodo::COLLECT_RADIO_IF_DONE, todo
  end

  test "off duty below the event radio limit prompts to issue a radio" do
    todo = RadioAccounting.radio_todo(off_duty: true, no_more_scheduled: false,
                                      accounting: accounting_for(event: 1, max: 2))

    assert_equal HqTodo::ISSUE_RADIO, todo
  end

  test "off duty with no radios prompts issue even when nothing more is scheduled" do
    todo = RadioAccounting.radio_todo(off_duty: true, no_more_scheduled: true,
                                      accounting: accounting_for(max: 2))

    assert_equal HqTodo::ISSUE_RADIO, todo
  end

  test "off duty at the event radio limit and still working does not nag" do
    todo = RadioAccounting.radio_todo(off_duty: true, no_more_scheduled: false,
                                      accounting: accounting_for(event: 2, max: 2))

    assert_nil todo
  end

  # --- radio_todo: person off duty, shift radios only (radio_max == 0) ---

  test "off duty shift-radio-only person with a radio out is nagged to collect" do
    todo = RadioAccounting.radio_todo(off_duty: true, no_more_scheduled: false,
                                      accounting: accounting_for(shift: 1, max: 0))

    assert_equal HqTodo::COLLECT_RADIO, todo
  end

  test "off duty shift-radio-only person holding an event radio is nagged to collect" do
    todo = RadioAccounting.radio_todo(off_duty: true, no_more_scheduled: false,
                                      accounting: accounting_for(event: 1, max: 0))

    assert_equal HqTodo::COLLECT_RADIO, todo
  end

  test "off duty shift-radio-only person with no radio is prompted to issue one" do
    todo = RadioAccounting.radio_todo(off_duty: true, no_more_scheduled: false,
                                      accounting: accounting_for(max: 0))

    assert_equal HqTodo::ISSUE_RADIO, todo
  end

  # --- HqTodo vocabulary ---

  # Ported from the Ember HqTodoLabels, except where upstream's wording uses the
  # employment vocabulary this project forbids in user-facing text: "(if done
  # working)" and "Working Burn Perimeter" are rephrased in volunteer terms.
  # The chips also follow house copy style rather than upstream's punctuation:
  # verb phrases ("Check Out Radio"), em dash clause separators, and no "(s)".
  # Short action chips stay Title Case; chips carrying a full clause after the
  # em dash use sentence case so the clause does not read as a heading.
  test "todo labels match the Ember HqTodoLabels in volunteer terminology" do
    expected = {
      HqTodo::COLLECT_RADIO => "Collect Radio",
      HqTodo::COLLECT_RADIO_IF_DONE => "Collect Radio (if done rangering)",
      HqTodo::DELIVERY_MESSAGE => "Deliver Messages",
      HqTodo::END_SHIFT => "End The Shift",
      HqTodo::ISSUE_RADIO => "Check Out Radio",
      HqTodo::MEAL_POG => "Issue Meal Pog (if qualified)",
      HqTodo::MEAL_POG_NONE => "No Meal Pog — Has Meal Pass",
      HqTodo::NO_RADIO => "On Burn Perimeter — may not need a radio",
      HqTodo::START_SHIFT => "Start A Shift",
      HqTodo::VERIFY_TIMESHEET => "Review Timesheet",
      HqTodo::OFF_SITE => "No more upcoming shifts — ask if finished rangering"
    }

    assert_equal expected, HqTodo::LABELS
    assert_predicate HqTodo::LABELS, :frozen?
    assert_not(HqTodo::LABELS.values.any? { |label| label.match?(/\b(work|working|worked|job|staff)\b/i) },
               "todo labels must not use employment vocabulary")
  end

  test "the eleven todo keys are distinct symbols" do
    keys = [HqTodo::COLLECT_RADIO, HqTodo::COLLECT_RADIO_IF_DONE, HqTodo::DELIVERY_MESSAGE,
            HqTodo::END_SHIFT, HqTodo::ISSUE_RADIO, HqTodo::MEAL_POG, HqTodo::MEAL_POG_NONE,
            HqTodo::NO_RADIO, HqTodo::OFF_SITE, HqTodo::START_SHIFT, HqTodo::VERIFY_TIMESHEET]

    assert_equal 11, keys.uniq.length
    assert keys.all?(Symbol)
    assert_equal keys.sort, HqTodo::LABELS.keys.sort
  end
end
