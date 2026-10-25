# frozen_string_literal: true

require "test_helper"

class Scheduling::PositionCreditCopiesControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include ActiveSupport::Testing::TimeHelpers

  setup do
    travel_to Time.zone.local(2026, 7, 1, 12, 0, 0)
    Rails.cache.clear
    Current.reset

    @admin = person(:active_ranger)
    @outsider = person(:echelon_ranger)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::EDIT_SLOTS, "Edit Slots")
    grant_role(@admin, Role::ADMIN)
    grant_role(@outsider, Role::EDIT_SLOTS)

    @position = positions(:training_lead)
    @other_position = positions(:ood_position)

    sign_in_as(@admin)
  end

  teardown do
    Current.reset
    travel_back
    Rails.cache.clear
  end

  def create_credit(position: @position, start_time: "2025-08-25 00:00", end_time: "2025-08-25 23:59", **attrs)
    PositionCredit.create!({ position_id: position.id, start_time:, end_time:,
                             credits_per_hour: 2.5, description: "Morning" }.merge(attrs))
  end

  def create_orphan_credit
    doomed = Position.create!(title: "Doomed Position", active: true)
    credit = create_credit(position: doomed)
    Position.where(id: doomed.id).delete_all
    credit
  end

  # Labor Day 2025 is September 1; Labor Day 2026 is September 7.
  LABOR_DAY_DIFF = 371

  test "denies access without the admin role" do
    sign_in_as(@outsider)

    get scheduling_new_position_credit_copy_path(year: 2025)

    assert_redirected_to me_root_path
    assert_equal "Admin role required to manage position credits.", flash[:error]
  end

  test "new defaults the day shift to the labor day difference" do
    create_credit

    get scheduling_new_position_credit_copy_path(year: 2025)

    assert_response :success
    assert_select "input[name=delta_days][value=?]", LABOR_DAY_DIFF.to_s
    assert_select "body", text: /Labor Day of 2025 is September 1/
    assert_select "body", text: /Labor Day of 2026 is September 7, 371 days later/
  end

  test "new groups the copyable credits by position" do
    mine = create_credit
    theirs = create_credit(position: @other_position)

    get scheduling_new_position_credit_copy_path(year: 2025)

    assert_response :success
    assert_select "input#copy-credit-#{mine.id}"
    assert_select "input#copy-credit-#{theirs.id}"
  end

  test "new restricts the listing to one position when given one" do
    mine = create_credit
    theirs = create_credit(position: @other_position)

    get scheduling_new_position_credit_copy_path(position_id: @position.id, year: 2025)

    assert_response :success
    assert_select "input#copy-credit-#{mine.id}"
    assert_select "input#copy-credit-#{theirs.id}", count: 0
  end

  test "new excludes credits whose position was deleted and says so" do
    orphan = create_orphan_credit
    create_credit

    get scheduling_new_position_credit_copy_path(year: 2025)

    assert_response :success
    assert_select "input#copy-credit-#{orphan.id}", count: 0
    assert_select "body", text: /Not listed below: 1 credit from 2025/
  end

  test "new warns when copying from the current year" do
    create_credit(start_time: "2026-08-25 00:00", end_time: "2026-08-25 23:59")

    get scheduling_new_position_credit_copy_path(year: 2026)

    assert_response :success
    assert_select "body", text: /Copying from the Current Year/
  end

  test "copies the selected credits with their times shifted" do
    credit = create_credit
    skipped = create_credit(description: "Not chosen")

    assert_difference "PositionCredit.count", 1 do
      post scheduling_position_credit_copies_path(year: 2025), params: {
        credit_ids: [credit.id],
        delta_days: LABOR_DAY_DIFF,
        delta_hours: 1,
        delta_minutes: 30
      }
    end

    copy = PositionCredit.order(:id).last
    assert_equal credit.start_time + LABOR_DAY_DIFF.days + 1.hour + 30.minutes, copy.start_time
    assert_equal credit.end_time + LABOR_DAY_DIFF.days + 1.hour + 30.minutes, copy.end_time
    assert_equal credit.position_id, copy.position_id
    assert_equal credit.credits_per_hour, copy.credits_per_hour
    assert_equal "Morning", copy.description
    assert_equal 2026, copy.reload.start_year
    assert_not_equal skipped.id, copy.id
    assert_redirected_to scheduling_position_credits_path(year: 2025)
    assert_equal "1 position credit copied.", flash[:success]
  end

  test "copies into a different position" do
    credit = create_credit

    post scheduling_position_credit_copies_path(year: 2025), params: {
      credit_ids: [credit.id],
      delta_days: LABOR_DAY_DIFF,
      new_position_id: @other_position.id
    }

    assert_equal @other_position.id, PositionCredit.order(:id).last.position_id
  end

  test "refuses to copy several positions into one" do
    mine = create_credit
    theirs = create_credit(position: @other_position)

    assert_no_difference "PositionCredit.count" do
      post scheduling_position_credit_copies_path(year: 2025), params: {
        credit_ids: [mine.id, theirs.id],
        delta_days: LABOR_DAY_DIFF,
        new_position_id: @position.id
      }
    end

    assert_response :unprocessable_entity
    assert_equal "Multiple positions cannot be copied into a single position.", flash[:error]
  end

  test "ignores submitted credits whose position was deleted" do
    credit = create_credit
    orphan = create_orphan_credit

    assert_difference "PositionCredit.count", 1 do
      post scheduling_position_credit_copies_path(year: 2025), params: {
        credit_ids: [credit.id, orphan.id],
        delta_days: LABOR_DAY_DIFF
      }
    end

    assert_equal credit.position_id, PositionCredit.order(:id).last.position_id
  end

  test "copying nothing reports an error" do
    create_credit

    assert_no_difference "PositionCredit.count" do
      post scheduling_position_credit_copies_path(year: 2025), params: { delta_days: LABOR_DAY_DIFF }
    end

    assert_response :unprocessable_entity
    assert_equal "Select at least one credit to copy.", flash[:error]
  end

  # to_i read "#{id}x" as the id and copied that credit.
  test "credit ids that are not ids copy nothing" do
    credit = create_credit

    assert_no_difference "PositionCredit.count" do
      post scheduling_position_credit_copies_path(year: 2025),
           params: { delta_days: LABOR_DAY_DIFF, credit_ids: ["", "abc", "#{credit.id}x"] }
    end

    assert_response :unprocessable_entity
    assert_equal "Select at least one credit to copy.", flash[:error]
  end

  test "preview re-renders the shifted times without copying" do
    credit = create_credit

    assert_no_difference "PositionCredit.count" do
      post scheduling_position_credit_copies_path(year: 2025), params: {
        preview: "1",
        credit_ids: [credit.id],
        delta_days: 10,
        delta_hours: 0,
        delta_minutes: 0
      }
    end

    assert_response :unprocessable_entity
    assert_select "input[name=delta_days][value='10']"
    assert_select "input#copy-credit-#{credit.id}[checked]"
    assert_select "body", text: /#{Regexp.escape((credit.start_time + 10.days).strftime(DateTimeHelper::MONTH_DAY_TIME_YEAR))}/
  end
end
