# frozen_string_literal: true

require "test_helper"

class Person::MissingRequestsControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include ActiveSupport::Testing::TimeHelpers
  include TimesheetAdminTestHelper
  include EscapedMarkupTestHelper

  setup do
    travel_to Time.zone.local(2026, 8, 30, 12, 0, 0)
    Rails.cache.clear
    Current.reset

    @target = person(:active_ranger)
    @admin = person(:auditor_ranger)
    @event_manager = person(:echelon_ranger)
    @timesheet_manager = person(:ranger_with_custom_gender)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::EVENT_MANAGEMENT, "Event Management")
    ensure_role(Role::TIMESHEET_MANAGEMENT, "Timesheet Management")

    grant_role(@admin, Role::ADMIN)
    grant_role(@event_manager, Role::EVENT_MANAGEMENT)
    grant_role(@timesheet_manager, Role::TIMESHEET_MANAGEMENT)

    Current.person = @admin

    @request_entry = create_request!(additional_notes: "Forgot to sign in, partner can confirm.")
  end

  teardown do
    Current.reset
    travel_back
    Rails.cache.clear
  end

  test "new renders for an event manager" do
    sign_in_as(@event_manager)

    get new_person_missing_request_path(@target, year: 2026)

    assert_response :success
    assert_select "form[action=?]", person_missing_requests_path(@target, year: 2026)
  end

  test "create submits a pending request on the person's behalf" do
    sign_in_as(@event_manager)

    assert_difference -> { TimesheetMissing.count } do
      post person_missing_requests_path(@target, year: 2026), params: {
        timesheet_missing: {
          position_id: positions(:khaki_supervisor).id,
          on_duty: "2026-08-27T10:00",
          off_duty: "2026-08-27T16:00",
          partner: "none",
          additional_notes: "Radio died, entry never created."
        }
      }
    end

    assert_redirected_to person_timesheets_path(@target, year: 2026)
    request = TimesheetMissing.order(:id).last
    assert_equal TimesheetMissing::STATUS_PENDING, request.review_status
    assert_equal @event_manager.id, request.create_person_id
    assert request.timesheet_missing_notes.where(type: TimesheetMissingNote::TYPE_HQ_WORKER).exists?
  end

  test "create without any note is rejected" do
    sign_in_as(@event_manager)

    assert_no_difference -> { TimesheetMissing.count } do
      post person_missing_requests_path(@target, year: 2026), params: {
        timesheet_missing: {
          position_id: positions(:khaki_supervisor).id,
          on_duty: "2026-08-27T10:00",
          off_duty: "2026-08-27T16:00",
          partner: "none"
        }
      }
    end

    assert_response :unprocessable_entity
  end

  test "a timesheet manager may create a request with only a reviewer note" do
    sign_in_as(@timesheet_manager)

    assert_difference -> { TimesheetMissing.count } do
      post person_missing_requests_path(@target, year: 2026), params: {
        timesheet_missing: {
          position_id: positions(:khaki_supervisor).id,
          on_duty: "2026-08-27T10:00",
          off_duty: "2026-08-27T16:00",
          partner: "none",
          additional_wrangler_notes: "Confirmed with the shift lead."
        }
      }
    end

    assert_redirected_to person_timesheets_path(@target, year: 2026)
  end

  test "update is denied to an event manager" do
    sign_in_as(@event_manager)

    patch person_missing_request_path(@target, @request_entry, year: 2026),
          params: { timesheet_missing: { review_status: TimesheetMissing::STATUS_APPROVED } }

    assert_redirected_to person_timesheets_path(@target, year: 2026)
    assert_equal TimesheetMissing::STATUS_PENDING, @request_entry.reload.review_status
  end

  test "approving with create entry creates the timesheet with a full audit trail" do
    confirm_timesheet_for(@target, 2026)
    sign_in_as(@timesheet_manager)

    assert_difference -> { Timesheet.count } do
      patch person_missing_request_path(@target, @request_entry, year: 2026), params: {
        save_and_next: "",
        timesheet_missing: {
          review_status: TimesheetMissing::STATUS_APPROVED,
          create_entry: "1",
          new_on_duty: "2026-08-27T10:00",
          new_off_duty: "2026-08-27T15:00",
          new_position_id: positions(:khaki_supervisor).id
        }
      }
    end

    assert_redirected_to person_timesheets_path(@target, year: 2026)

    @request_entry.reload
    assert_equal TimesheetMissing::STATUS_APPROVED, @request_entry.review_status
    assert_equal @timesheet_manager.id, @request_entry.reviewer_person_id
    assert_not_nil @request_entry.reviewed_at

    timesheet = Timesheet.order(:id).last
    assert_equal @target.id, timesheet.person_id
    assert_equal positions(:khaki_supervisor).id, timesheet.position_id
    assert_equal Time.zone.local(2026, 8, 27, 15, 0, 0), timesheet.off_duty

    assert TimesheetLog.where(timesheet_id: timesheet.id, action: TimesheetLog::CREATED).exists?
    copied = timesheet.timesheet_notes.where("note LIKE ?", "[copied from Missing Timesheet request]%")
    assert copied.exists?
    assert timesheet.timesheet_notes.where(type: TimesheetNote::TYPE_ADMIN).exists?
    assert @request_entry.timesheet_missing_notes
                         .where(type: TimesheetMissingNote::TYPE_ADMIN)
                         .where("note LIKE ?", "Timesheet ##{timesheet.id} created.%").exists?

    assert_not PersonEvent.find_for_person_year(@target.id, 2026).timesheet_confirmed
  end

  test "approving with create entry fails when the person does not hold the position" do
    sign_in_as(@timesheet_manager)

    assert_no_difference -> { Timesheet.count } do
      patch person_missing_request_path(@target, @request_entry, year: 2026), params: {
        timesheet_missing: {
          review_status: TimesheetMissing::STATUS_APPROVED,
          create_entry: "1",
          new_on_duty: "2026-08-27T10:00",
          new_off_duty: "2026-08-27T15:00",
          new_position_id: positions(:ood_position).id
        }
      }
    end

    assert_response :unprocessable_entity
    assert_equal TimesheetMissing::STATUS_PENDING, @request_entry.reload.review_status
  end

  # The header names the entry's position and time, and the time is markup.
  test "edit renders the entry's time in its header rather than its tags" do
    sign_in_as(@timesheet_manager)

    get edit_person_missing_request_path(@target, @request_entry, year: 2026)

    assert_response :success
    assert_no_escaped_markup
  end

  test "update and review next redirects to the next pending request" do
    later_request = create_request!(additional_notes: "Second missing shift.",
                                    on_duty: Time.zone.local(2026, 8, 29, 10, 0, 0),
                                    off_duty: Time.zone.local(2026, 8, 29, 14, 0, 0))
    sign_in_as(@timesheet_manager)

    patch person_missing_request_path(@target, @request_entry, year: 2026), params: {
      save_and_next: "1",
      timesheet_missing: { review_status: TimesheetMissing::STATUS_REJECTED,
                           additional_wrangler_notes: "No record of the shift." }
    }

    assert_redirected_to edit_person_missing_request_path(@target, later_request, year: 2026)
    assert_equal TimesheetMissing::STATUS_REJECTED, @request_entry.reload.review_status
  end

  test "show renders read-only for an event manager" do
    sign_in_as(@event_manager)

    get person_missing_request_path(@target, @request_entry, year: 2026)

    assert_response :success
    # main: the navbar mega menu keeps its star form on every page
    assert_select "main form", count: 0
  end

  test "destroy deletes the request" do
    sign_in_as(@timesheet_manager)

    assert_difference -> { TimesheetMissing.count }, -1 do
      delete person_missing_request_path(@target, @request_entry, year: 2026)
    end

    assert_redirected_to person_timesheets_path(@target, year: 2026)
  end

  private

  def create_request!(additional_notes:,
                      on_duty: Time.zone.local(2026, 8, 27, 10, 0, 0),
                      off_duty: Time.zone.local(2026, 8, 27, 16, 0, 0))
    TimesheetMissing.create!(
      person_id: @target.id,
      create_person_id: @target.id,
      position_id: positions(:khaki_supervisor).id,
      on_duty: on_duty,
      off_duty: off_duty,
      partner: "none",
      review_status: TimesheetMissing::STATUS_PENDING,
      additional_notes: additional_notes
    )
  end
end
