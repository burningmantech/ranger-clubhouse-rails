# frozen_string_literal: true

require "test_helper"

class TimesheetTest < ActiveSupport::TestCase
  include AlphaPositionTestHelper
  include ActiveSupport::Testing::TimeHelpers

  setup do
    travel_to Time.zone.local(2026, 4, 14, 12, 0, 0)
    Current.reset
    Current.person = person(:auditor_ranger)

    @entry = timesheet(:active_ranger_ood_2023_1)
  end

  teardown do
    Current.reset
    travel_back
  end

  # Runs the years query directly: test_helper stubs YearsManagement, the only
  # caller, so no other test reaches this SQL.
  test "a 2025 Alpha shift counts as a Ranger year after an Alpha pass, not another position's pass" do
    setup_alpha_position
    setup_cheetah_cub_position
    alpha = person(:alpha_ranger)
    mentor = person(:active_ranger)
    Timesheet.insert_all!([{ person_id: alpha.id, position_id: Position::ALPHA, is_echelon: false,
                             on_duty: Time.utc(2025, 8, 25, 10), off_duty: Time.utc(2025, 8, 25, 18) }])
    PersonMentor.create!(person: alpha, mentor:, mentor_year: 2025, position_id: Position::CHEETAH_CUB,
                         status: PersonMentor::STATUS_PASS)

    assert_not_includes Timesheet.compute_years_for_person(alpha.id, Timesheet::YEARS_AS_RANGER), 2025

    PersonMentor.create!(person: alpha, mentor:, mentor_year: 2025, status: PersonMentor::STATUS_PASS)

    assert_includes Timesheet.compute_years_for_person(alpha.id, Timesheet::YEARS_AS_RANGER), 2025
  end

  test "updating times logs an UPDATE with the old and new values" do
    old_off_duty = @entry.off_duty
    new_off_duty = old_off_duty + 1.hour

    @entry.off_duty = new_off_duty
    @entry.save!(validate: false)

    update_log = TimesheetLog.find_by(timesheet_id: @entry.id, action: TimesheetLog::UPDATE)
    assert_not_nil update_log
    assert_equal [old_off_duty.to_s, new_off_duty.to_s], update_log.data["off_duty"]
    assert_equal Current.person_id, update_log.create_person_id
  end

  test "marking an entry verified logs VERIFY and no UPDATE" do
    @entry.update_column(:review_status, Timesheet::STATUS_UNVERIFIED)

    @entry.review_status = Timesheet::STATUS_VERIFIED
    @entry.save!(validate: false)

    assert TimesheetLog.exists?(timesheet_id: @entry.id, action: TimesheetLog::VERIFY)
    assert_not TimesheetLog.exists?(timesheet_id: @entry.id, action: TimesheetLog::UPDATE)
  end

  test "marking an entry unverified logs UNVERIFIED and no UPDATE" do
    @entry.review_status = Timesheet::STATUS_UNVERIFIED
    @entry.save!(validate: false)

    assert TimesheetLog.exists?(timesheet_id: @entry.id, action: TimesheetLog::UNVERIFIED)
    assert_not TimesheetLog.exists?(timesheet_id: @entry.id, action: TimesheetLog::UPDATE)
  end

  test "verification alongside another change logs both the UPDATE and VERIFY" do
    @entry.update_column(:review_status, Timesheet::STATUS_UNVERIFIED)
    old_position_id = @entry.position_id

    @entry.position_id = positions(:mentor_lead).id
    @entry.review_status = Timesheet::STATUS_VERIFIED
    @entry.save!(validate: false)

    update_log = TimesheetLog.find_by(timesheet_id: @entry.id, action: TimesheetLog::UPDATE)
    assert_not_nil update_log
    assert_equal [old_position_id, positions(:mentor_lead).id], update_log.data["position_id"]
    assert_equal [Timesheet::STATUS_UNVERIFIED, Timesheet::STATUS_VERIFIED], update_log.data["review_status"]
    assert TimesheetLog.exists?(timesheet_id: @entry.id, action: TimesheetLog::VERIFY)
  end

  test "a non-verification status change is logged as an UPDATE" do
    @entry.review_status = Timesheet::STATUS_PENDING
    @entry.save!(validate: false)

    update_log = TimesheetLog.find_by(timesheet_id: @entry.id, action: TimesheetLog::UPDATE)
    assert_not_nil update_log
    assert_equal [Timesheet::STATUS_VERIFIED, Timesheet::STATUS_PENDING], update_log.data["review_status"]
  end

  test "moving on_duty to another year moves the entry's logs to that year" do
    TimesheetLog.record(TimesheetLog::CREATED, @entry.person_id, Current.person_id, @entry.id, nil, 2023)

    @entry.on_duty += 1.year
    @entry.off_duty += 1.year
    @entry.save!(validate: false)

    assert_equal [2024], TimesheetLog.where(timesheet_id: @entry.id).distinct.pluck(:year)
  end

  test "creating an entry does not write UPDATE or VERIFY logs" do
    entry = Timesheet.new(
      person_id: person(:active_ranger).id,
      position_id: positions(:ood_position).id,
      on_duty: Time.zone.local(2026, 4, 10, 10, 0, 0),
      off_duty: Time.zone.local(2026, 4, 10, 12, 0, 0),
      review_status: Timesheet::STATUS_VERIFIED
    )
    entry.save!(validate: false)

    assert_empty TimesheetLog.where(timesheet_id: entry.id)
  end

  test "changing duty times rebuilds awards, and unrelated changes do not" do
    rebuilt = []
    capturing_award_rebuilds(rebuilt) do
      @entry.off_duty += 1.hour
      @entry.save!(validate: false)
    end
    assert_equal [@entry.person_id], rebuilt

    rebuilt.clear
    capturing_award_rebuilds(rebuilt) do
      @entry.is_echelon = true
      @entry.save!(validate: false)
    end
    assert_empty rebuilt
  end

  private

  def capturing_award_rebuilds(rebuilt)
    original = AwardManagement.method(:rebuild_for_person_id)
    AwardManagement.define_singleton_method(:rebuild_for_person_id) { |person_id| rebuilt << person_id }
    yield
  ensure
    AwardManagement.define_singleton_method(:rebuild_for_person_id, original)
  end
end
