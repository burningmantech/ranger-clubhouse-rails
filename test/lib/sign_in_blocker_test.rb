# frozen_string_literal: true

require "test_helper"

# Proves the +now:+ parameter on SignInBlocker.check is a REAL seam, not a
# pseudo-parameterised one: the instant handed in at the boundary wholly governs the
# training year that is checked.
#
# Before this seam existed, +check+ accepted +relative_to:+ for slot timing but
# +check_for_training+ re-read +Current.year+ deep in its body — so passing a past instant
# silently checked the wrong (present) training year. These tests pin that the year of the
# instant passed in now flows through, and that omitting +now:+ still tracks Current
# (existing callers unchanged).
#
# The production caller that needs this is ShiftManage.sign_in's backdated check-in:
# ShiftManage.check_in_time rolls a "HH:MM" start time backwards, and on New Year's Eve
# that crosses midnight into the previous year. The blockers must then read the training
# year the shift actually started in, not the year it is being recorded in.
class SignInBlockerTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  # Minimal duck-typed stand-ins so the test exercises the seam without ~40 fixture records.
  class FakePerson
    attr_reader :id, :status, :employee_id

    def initialize(id: 1, status: Person::ACTIVE, employee_id: 99)
      @id = id
      @status = status
      @employee_id = employee_id
    end
  end

  class FakePosition
    attr_reader :id, :type, :paycode, :training_position_id

    def initialize(paycode: nil)
      @id = 500
      @type = "Frontline"
      @paycode = paycode
      @training_position_id = nil
    end

    def no_training_required = false
    def allow_echelon = false
    def is_checkin_time_restricted = false
  end

  # Record every year SignInBlocker hands to the training check. Minitest 6 dropped
  # Object#stub, so swap the class method by hand and restore the captured Method in
  # ensure. (Safe here because did_person_pass_for_year? is a plain def self.; never do
  # this to Rails.cache -- see test/support/cache_test_helper.rb.)
  def capture_training_years
    queried = []
    original = Training.method(:did_person_pass_for_year?)
    Training.define_singleton_method(:did_person_pass_for_year?) do |_person, _position_id, year|
      queried << year
      true # passed -- keeps the blocker list empty; we only care which year was asked
    end
    yield
    queried
  ensure
    Training.define_singleton_method(:did_person_pass_for_year?, original)
  end

  test "check_for_training queries the year of the instant passed in, not Current" do
    person = FakePerson.new
    position = FakePosition.new

    years = travel_to Time.zone.local(2026, 8, 25, 12, 0, 0) do
      # An instant in the PRIOR year must drive the training-year that gets checked,
      # even though Current is sitting in 2026.
      capture_training_years do
        SignInBlocker.check(person, position, now: Time.zone.local(2025, 8, 25, 12, 0, 0))
      end
    end

    assert_equal [2025], years,
      "the training check must use the year of the instant passed in, proving the param is not dead"
  end

  test "an instant in the current year and one a year earlier check different training years" do
    person = FakePerson.new
    position = FakePosition.new

    this_year = capture_training_years do
      SignInBlocker.check(person, position, now: Time.zone.local(2026, 8, 25, 12, 0, 0))
    end
    last_year = capture_training_years do
      SignInBlocker.check(person, position, now: Time.zone.local(2025, 8, 25, 12, 0, 0))
    end

    assert_equal [2026], this_year
    assert_equal [2025], last_year
    refute_equal this_year, last_year, "shifting the instant's year must shift the year checked"
  end

  test "the default instant (no arg) tracks Current — existing callers keep working" do
    person = FakePerson.new
    position = FakePosition.new

    years = nil
    current_year = nil
    travel_to Time.zone.local(2024, 9, 1, 10, 0, 0) do
      current_year = Current.year
      years = capture_training_years do
        SignInBlocker.check(person, position) # no now: — relies on Current.time
      end
    end

    assert_equal [current_year], years, "the default instant must track Current, keeping existing callers working"
    assert_equal [2024], years
  end

  # "0" clears someone to work a paid shift unpaid. An ID stored as "" or spaces,
  # written around Person's setter, is still no ID.
  test "a paid position blocks a blank employee id but not the 0" do
    position = FakePosition.new(paycode: "DIRT")

    blocked = [nil, "", "  ", "0", "1234"].select do |employee_id|
      blockers = nil
      capture_training_years { blockers = SignInBlocker.check(FakePerson.new(employee_id:), position) }
      blockers.include?({ blocker: Timesheet::BLOCKED_NO_EMPLOYEE_ID })
    end

    assert_equal [nil, "", "  "], blocked
  end
end
