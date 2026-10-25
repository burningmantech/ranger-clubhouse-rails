# frozen_string_literal: true

require "test_helper"

class PayrollExportReportTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  YEAR = 2025

  setup do
    Rails.cache.clear
    Current.reset

    @now = Time.zone.local(YEAR, 9, 1, 21, 0, 0)
    travel_to @now

    @ranger = person(:active_ranger)
    @ranger.update!(employee_id: "E-1001")

    @position = Position.create!(title: "Payroll Dirt", active: true, paycode: "DIRT")
  end

  teardown do
    travel_back
    Current.reset
    Rails.cache.clear
  end

  def at(hour, minute = 0, second = 0, day: 1)
    Time.zone.local(YEAR, 9, day, hour, minute, second)
  end

  def create_entry(on_duty:, off_duty: nil, position: @position, who: @ranger,
                   review_status: Timesheet::STATUS_UNVERIFIED)
    Timesheet.create!(person: who, position:, on_duty:, off_duty:, review_status:,
                      additional_notes: "test shift")
  end

  def run_report(start_time: at(0), end_time: at(23, 59), break_after_hours: 0,
                 break_duration_minutes: 0, position_ids: nil)
    PayrollExportReport.execute(start_time:, end_time:, break_after_hours:,
                                break_duration_minutes:,
                                position_ids: position_ids || [@position.id])
  end

  def only_shift(result) = result.people.first.shifts.first

  test "an entry open since before the window still appears" do
    create_entry(on_duty: at(4))

    result = run_report(start_time: at(8), end_time: at(20))

    assert_equal 1, result.people.size
    assert only_shift(result).still_on_duty
  end

  test "an open entry is measured up to now" do
    create_entry(on_duty: at(19))

    shift = only_shift(run_report)

    assert_equal 2.hours.to_i, shift.orig_duration
  end

  # The stand-in end for an entry no one closed is money: left unbounded, a
  # sign-in forgotten weeks ago is paid through to whenever the page was opened.
  test "an open entry is never measured past the end of the pay period" do
    create_entry(on_duty: at(6))

    shift = only_shift(run_report(start_time: at(0), end_time: at(10)))

    assert_equal at(10), shift.orig_off_duty
    assert_equal 4.hours.to_i, shift.orig_duration
  end

  test "an open entry starting in the future never ends before it began" do
    create_entry(on_duty: at(22))

    shift = only_shift(run_report(start_time: at(0), end_time: at(23)))

    assert_equal shift.orig_on_duty, shift.orig_off_duty
    assert_equal 0, shift.orig_duration
  end

  # An entry left open at a past event is the ordinary case here -- the Mass
  # Signout page exists because they accumulate. Counted from its sign-in it
  # reports years of hours and writes a punch pair reaching back to them.
  test "an entry left open long ago is paid only for the pay period" do
    create_entry(on_duty: at(9, day: 1) - 2.years)

    shift = only_shift(run_report(start_time: at(0, day: 1), end_time: at(12, day: 1)))

    assert_equal at(0, day: 1), shift.orig_on_duty
    assert_equal 12.hours.to_i, shift.orig_duration
    assert_equal 12.hours.to_i, shift.payable_duration
  end

  # A clerk preparing next week's run, or a server whose clock is held back.
  test "a pay period opening after now never punches out before it punches in" do
    create_entry(on_duty: at(9))

    shift = only_shift(run_report(start_time: at(9, day: 5), end_time: at(17, day: 5)))

    assert_operator shift.off_duty, :>=, shift.on_duty
    assert_operator shift.orig_off_duty, :>=, shift.orig_on_duty
    assert_equal 0, shift.payable_duration
  end

  test "an entry clipped at the end says so, even when it is still open" do
    create_entry(on_duty: at(6))

    shift = only_shift(run_report(start_time: at(0), end_time: at(10)))

    assert_match(/Truncated end time/, shift.notes_text)
    assert_match(/Still on duty/, shift.notes_text)
  end

  # The window bounds are compared as wall clock. Bound as times they are
  # rewritten into the machine's zone, which is not the application's, and the
  # last hour of every winter pay period silently drops out.
  test "the pay period keeps its boundaries in a month the zones disagree" do
    december = Time.zone.local(YEAR, 12, 10, 23, 30, 0)
    create_entry(on_duty: december, off_duty: december + 20.minutes)

    result = PayrollExportReport.execute(start_time: Time.zone.local(YEAR, 12, 10, 0, 0, 0),
                                         end_time: Time.zone.local(YEAR, 12, 11, 0, 0, 0),
                                         break_after_hours: 0, break_duration_minutes: 0,
                                         position_ids: [@position.id])

    assert_equal 1, result.people.size, "an entry in the last hour must not drop out"
    assert_equal 20.minutes.to_i, result.people.first.shifts.first.payable_duration
  end

  # The break has to fit between the two halves. When it cannot, the shift is
  # left whole -- a second half ending before it started would pay negative time.
  test "a meal break that does not fit leaves the shift whole" do
    create_entry(on_duty: at(6), off_duty: at(12))

    shift = only_shift(run_report(break_after_hours: 5, break_duration_minutes: 90))

    assert_nil shift.meal_break
    # The distinguishing fragment, not just "meal break" -- all three reasons
    # for leaving a shift whole contain that, so the loose match could not tell
    # a clerk being given the wrong explanation.
    assert_match(/not long enough to fit both halves/, shift.notes_text)
  end

  test "an entry clipped to under a minute is kept and says so" do
    create_entry(on_duty: at(5, 59, 50), off_duty: at(6, 0, 20))

    result = run_report(start_time: at(6), end_time: at(18))
    shift = only_shift(result)

    assert_equal 1, result.people.first.shifts.size
    assert_equal 20, shift.duration
    assert_match(/under a minute/, shift.notes_text)
  end

  # The padded ones are written around Person's setter, which would save them as
  # "0". Payroll Missing ID lists all three as set to 0, so none may be exported.
  test "an employee id of zero is left out of the report entirely, padded or not" do
    create_entry(on_duty: at(9), off_duty: at(12))

    ["0", "0 ", "0\u00A0"].each do |zero|
      @ranger.update_column(:employee_id, zero)

      result = run_report(start_time: at(8), end_time: at(20))

      assert_empty result.people, "#{zero.inspect} is the 0"
      assert_empty result.people_without_ids
    end
  end

  test "a person with no employee id is listed apart" do
    @ranger.update!(employee_id: nil)
    create_entry(on_duty: at(9), off_duty: at(12))

    result = run_report(start_time: at(8), end_time: at(20))

    assert_empty result.people
    assert_equal [@ranger.id], result.people_without_ids.map(&:id)
  end

  test "an entry overhanging both ends is clipped and says so twice" do
    create_entry(on_duty: at(6), off_duty: at(20))

    shift = only_shift(run_report(start_time: at(8), end_time: at(18)))

    assert_equal at(8), shift.on_duty
    assert_equal at(18), shift.off_duty
    assert_equal 10.hours.to_i, shift.duration
    assert_match(/Truncated start time/, shift.notes_text)
    assert_match(/Truncated end time/, shift.notes_text)
  end

  # The Hours column still shows the whole recorded shift, but the figure that
  # is totalled is the time inside the period -- which is what the punch file
  # pays. The two used to disagree, so the page could not be reconciled with it.
  test "a clipped shift is paid only for the time inside the pay period" do
    create_entry(on_duty: at(6), off_duty: at(20))

    shift = only_shift(run_report(start_time: at(8), end_time: at(18)))

    assert_equal 14.hours.to_i, shift.orig_duration
    assert_equal 10.hours.to_i, shift.payable_duration
  end

  # More of a shift inside the period must never be worth less than less of it.
  test "pay does not fall as more of a shift moves inside the pay period" do
    create_entry(on_duty: at(6), off_duty: at(18))

    payables = [12, 10, 8].map do |start_hour|
      only_shift(run_report(start_time: at(start_hour), end_time: at(18),
                            break_after_hours: 4, break_duration_minutes: 60)).payable_duration
    end

    assert_equal payables.sort, payables
  end

  test "a long shift is cut in two around the meal break" do
    create_entry(on_duty: at(6, 45), off_duty: at(15))

    result = run_report(break_after_hours: 4, break_duration_minutes: 60)
    shift = only_shift(result)

    assert_equal at(6, 45), shift.meal_break.first_on_duty
    assert_equal at(10, 45), shift.meal_break.first_off_duty
    assert_equal at(11, 45), shift.meal_break.second_on_duty
    assert_equal at(15), shift.meal_break.second_off_duty
  end

  test "a cut shift is paid its own length less the break" do
    create_entry(on_duty: at(6, 45), off_duty: at(15))

    shift = only_shift(run_report(break_after_hours: 4, break_duration_minutes: 60))

    assert_equal 8.hours.to_i + 15.minutes.to_i, shift.orig_duration
    assert_equal 7.hours.to_i + 15.minutes.to_i, shift.payable_duration
  end

  test "a position set to not adjust hours is never cut" do
    @position.update!(no_payroll_hours_adjustment: true)
    create_entry(on_duty: at(6), off_duty: at(16))

    shift = only_shift(run_report(break_after_hours: 4, break_duration_minutes: 60))

    assert_nil shift.meal_break
    assert_match(/not adjust hours/, shift.notes_text)
  end

  test "a shift under six hours is left whole and says why" do
    create_entry(on_duty: at(8), off_duty: at(13))

    shift = only_shift(run_report(break_after_hours: 4, break_duration_minutes: 60))

    assert_nil shift.meal_break
    assert_match(/less than 6 hours/, shift.notes_text)
  end

  test "a shift not a full hour past the threshold is left whole" do
    create_entry(on_duty: at(6), off_duty: at(12, 30))

    shift = only_shift(run_report(break_after_hours: 6, break_duration_minutes: 60))

    assert_nil shift.meal_break
    assert_match(/did not exceed the break-after threshold/, shift.notes_text)
  end

  test "turning meal breaks off leaves every shift whole and unremarked" do
    create_entry(on_duty: at(6), off_duty: at(16))

    shift = only_shift(run_report(break_after_hours: 0, break_duration_minutes: 60))

    assert_nil shift.meal_break
    assert_empty shift.notes
  end

  test "an approved entry counts as checked off, like a verified one" do
    create_entry(on_duty: at(9), off_duty: at(12), review_status: Timesheet::STATUS_APPROVED)

    assert only_shift(run_report).verified
  end

  test "a verified entry counts as checked off" do
    create_entry(on_duty: at(9), off_duty: at(12), review_status: Timesheet::STATUS_VERIFIED)

    assert only_shift(run_report).verified
  end

  test "an unverified entry is one to look at" do
    create_entry(on_duty: at(9), off_duty: at(12))

    shift = only_shift(run_report)

    assert_not shift.verified
    assert shift.needs_review?
  end

  test "people are listed by callsign whatever case it is written in" do
    other = person(:auditor_ranger)
    other.update!(employee_id: "E-2002", callsign: "aardvark")
    @ranger.update!(callsign: "Zebra")
    create_entry(on_duty: at(9), off_duty: at(12))
    create_entry(on_duty: at(9), off_duty: at(12), who: other)

    assert_equal %w[aardvark Zebra], run_report.people.map(&:callsign)
  end

  test "a person's shifts are listed in the order they were worked" do
    create_entry(on_duty: at(14), off_duty: at(16))
    create_entry(on_duty: at(6), off_duty: at(8))

    assert_equal [at(6), at(14)], run_report.people.first.shifts.map(&:orig_on_duty)
  end

  test "entries for positions no one asked for are left out" do
    other_position = Position.create!(title: "Payroll Ops", active: true, paycode: "OPS")
    create_entry(on_duty: at(9), off_duty: at(12), position: other_position)

    assert run_report(position_ids: [@position.id]).empty?
  end

  test "a closed entry ending before the window opens is left out" do
    create_entry(on_duty: at(1), off_duty: at(2))

    assert run_report(start_time: at(8), end_time: at(20)).empty?
  end

  test "an entry starting after the window closes is left out" do
    create_entry(on_duty: at(21), off_duty: at(22))

    assert run_report(start_time: at(8), end_time: at(20)).empty?
  end

  test "totals add up across people" do
    other = person(:auditor_ranger)
    other.update!(employee_id: "E-2002")
    create_entry(on_duty: at(6), off_duty: at(8))
    create_entry(on_duty: at(9), off_duty: at(12), who: other)

    result = run_report

    assert_equal 5.hours.to_i, result.grand_total
    assert_equal 2, result.entry_count
    assert_equal 2, result.person_count
  end
end
