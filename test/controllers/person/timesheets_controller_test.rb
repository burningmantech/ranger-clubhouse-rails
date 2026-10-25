# frozen_string_literal: true

require "test_helper"

class Person::TimesheetsControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include ActiveSupport::Testing::TimeHelpers
  include ActiveJob::TestHelper
  include TimesheetAdminTestHelper

  setup do
    travel_to Time.zone.local(2026, 8, 30, 12, 0, 0)
    Rails.cache.clear
    Current.reset

    @target = person(:active_ranger)
    @admin = person(:auditor_ranger)
    @event_manager = person(:echelon_ranger)
    @timesheet_manager = person(:ranger_with_custom_gender)
    @trainer = person(:retired_ranger)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::EVENT_MANAGEMENT, "Event Management")
    ensure_role(Role::TIMESHEET_MANAGEMENT, "Timesheet Management")
    ensure_role(Role::TRAINER, "Trainer")

    grant_role(@admin, Role::ADMIN)
    grant_role(@event_manager, Role::EVENT_MANAGEMENT)
    grant_role(@timesheet_manager, Role::TIMESHEET_MANAGEMENT)
    grant_role(@trainer, Role::TRAINER)

    Current.person = @admin

    @entry = create_timesheet!(
      position: positions(:khaki_supervisor),
      on_duty: Time.zone.local(2026, 8, 28, 10, 0, 0),
      off_duty: Time.zone.local(2026, 8, 28, 16, 0, 0),
      review_status: Timesheet::STATUS_UNVERIFIED
    )
  end

  teardown do
    Current.reset
    travel_back
    Rails.cache.clear
  end

  test "index renders entries and missing requests for an event manager" do
    sign_in_as(@event_manager)

    get person_timesheets_path(@target, year: 2026)

    assert_response :success
    assert_select "td", text: /Khaki Supervisor/
    assert_select "a[href=?]", new_person_missing_request_path(@target, year: 2026)
    # No Shift Management role: the check in/out page is not offered.
    assert_select "a[href=?]", person_shift_manage_path(@target), count: 0
  end

  test "index is denied to the person-page roles without timesheet access" do
    sign_in_as(@trainer)

    get person_timesheets_path(@target, year: 2026)

    assert_redirected_to me_root_path
  end

  test "edit renders read-only for an event manager and a form for a timesheet manager" do
    sign_in_as(@event_manager)
    get edit_person_timesheet_path(@target, @entry, year: 2026)
    assert_response :success
    assert_select "form[action=?]", person_timesheet_path(@target, @entry, year: 2026), count: 0

    sign_in_as(@timesheet_manager)
    get edit_person_timesheet_path(@target, @entry, year: 2026)
    assert_response :success
    assert_select "form[action=?]", person_timesheet_path(@target, @entry, year: 2026)
  end

  test "update is denied to an event manager" do
    sign_in_as(@event_manager)

    patch person_timesheet_path(@target, @entry, year: 2026),
          params: { timesheet: { review_status: Timesheet::STATUS_VERIFIED } }

    assert_redirected_to person_timesheets_path(@target, year: 2026)
    assert_equal Timesheet::STATUS_UNVERIFIED, @entry.reload.review_status
  end

  test "marking an entry verified records the verification and a VERIFY log" do
    sign_in_as(@timesheet_manager)

    patch person_timesheet_path(@target, @entry, year: 2026),
          params: { timesheet: { review_status: Timesheet::STATUS_VERIFIED,
                                 additional_wrangler_notes: "Looks good" } }

    assert_redirected_to person_timesheets_path(@target, year: 2026)
    @entry.reload
    assert_equal Timesheet::STATUS_VERIFIED, @entry.review_status
    assert_equal @timesheet_manager.id, @entry.verified_person_id
    assert_equal @timesheet_manager.id, @entry.reviewer_person_id
    assert_not_nil @entry.verified_at
    assert TimesheetLog.where(timesheet_id: @entry.id, action: TimesheetLog::VERIFY).exists?
    assert @entry.timesheet_notes.where(type: TimesheetNote::TYPE_WRANGLER).exists?
  end

  test "a non-verified status change logs the update and un-confirms the timesheet" do
    confirm_timesheet_for(@target, 2026)
    sign_in_as(@timesheet_manager)

    patch person_timesheet_path(@target, @entry, year: 2026),
          params: { timesheet: { review_status: Timesheet::STATUS_PENDING } }

    assert_redirected_to person_timesheets_path(@target, year: 2026)
    update_log = TimesheetLog.where(timesheet_id: @entry.id, action: TimesheetLog::UPDATE).last
    assert_equal %w[unverified pending], update_log.data["review_status"]
    assert_not PersonEvent.find_for_person_year(@target.id, 2026).timesheet_confirmed
    assert TimesheetLog.where(timesheet_id: @entry.id, action: TimesheetLog::UNCONFIRMED).exists?
  end

  test "a time change is recorded in the audit log with old and new values" do
    sign_in_as(@timesheet_manager)
    old_off_duty = @entry.off_duty

    patch person_timesheet_path(@target, @entry, year: 2026),
          params: { timesheet: { off_duty: "2026-08-28T17:30" } }

    update_log = TimesheetLog.where(timesheet_id: @entry.id, action: TimesheetLog::UPDATE).last
    assert_not_nil update_log
    assert_equal old_off_duty.to_s, update_log.data["off_duty"][0]
    assert_includes update_log.data["off_duty"][1], "17:30"
  end

  test "signoff ends an on-duty shift and logs it" do
    on_duty_entry = create_timesheet!(
      position: positions(:khaki_supervisor),
      on_duty: Time.zone.local(2026, 8, 30, 8, 0, 0),
      off_duty: nil,
      review_status: Timesheet::STATUS_UNVERIFIED
    )
    sign_in_as(@admin)

    post signoff_person_timesheet_path(@target, on_duty_entry, year: 2026)

    # Lands on the check in/out page, not the entries list.
    assert_redirected_to person_shift_manage_path(@target)
    assert_equal Current.time, on_duty_entry.reload.off_duty
    assert TimesheetLog.where(timesheet_id: on_duty_entry.id, action: TimesheetLog::SIGNOFF).exists?

    post signoff_person_timesheet_path(@target, on_duty_entry, year: 2026)
    assert_redirected_to person_shift_manage_path(@target)
    assert_equal "#{@target.callsign} was already signed off that shift.", flash[:error]
  end

  test "signoff converts an inactive person back to active and mails the VCs" do
    inactive = person(:inactive_ranger)
    on_duty_entry = create_timesheet!(
      person: inactive,
      position: positions(:khaki_supervisor),
      on_duty: Time.zone.local(2026, 8, 30, 8, 0, 0),
      off_duty: nil,
      review_status: Timesheet::STATUS_UNVERIFIED
    )
    sign_in_as(@admin)

    assert_enqueued_emails 1 do
      post signoff_person_timesheet_path(inactive, on_duty_entry, year: 2026)
    end

    assert_equal Person::ACTIVE, inactive.reload.status
    # The conversion is delivered by the modal on the check in/out page.
    assert_redirected_to person_shift_manage_path(inactive)
    assert_no_match(/Active/, flash[:success])
    follow_redirect!
    assert_select "dialog#shift-converted-modal", text: /#{inactive.callsign}.s account was Inactive/
  end

  # Timesheet Management alone may end a shift but cannot open the check in/out
  # page, so the redirect and the conversion notice fall back to the list.
  test "signoff without shift management returns to the entries list with the conversion in the toast" do
    inactive = person(:inactive_ranger)
    on_duty_entry = create_timesheet!(
      person: inactive,
      position: positions(:khaki_supervisor),
      on_duty: Time.zone.local(2026, 8, 30, 8, 0, 0),
      off_duty: nil,
      review_status: Timesheet::STATUS_UNVERIFIED
    )
    sign_in_as(@timesheet_manager)

    post signoff_person_timesheet_path(inactive, on_duty_entry, year: 2026)

    assert_redirected_to person_timesheets_path(inactive, year: 2026)
    assert_equal Person::ACTIVE, inactive.reload.status
    assert_match(/converted to Active/, flash[:success])
    assert_nil flash[:status_converted]
  end

  test "confirm toggles the timesheet confirmation and only logs actual changes" do
    sign_in_as(@admin)

    post confirm_person_timesheets_path(@target, year: 2026, confirmed: 1)
    event = PersonEvent.find_for_person_year(@target.id, 2026)
    assert event.timesheet_confirmed
    assert_equal 1, confirmation_log_count

    post confirm_person_timesheets_path(@target, year: 2026, confirmed: 1)
    assert_equal 1, confirmation_log_count

    post confirm_person_timesheets_path(@target, year: 2026, confirmed: 0)
    assert_not event.reload.timesheet_confirmed
    assert TimesheetLog.where(person_id: @target.id, action: TimesheetLog::UNCONFIRMED, timesheet_id: nil).exists?
  end

  test "backfill is admin-only" do
    sign_in_as(@timesheet_manager)

    get backfill_person_timesheets_path(@target)

    assert_redirected_to person_timesheets_path(@target, year: 2026)
  end

  test "backfill form renders for an admin" do
    sign_in_as(@admin)

    get backfill_person_timesheets_path(@target)

    assert_response :success
    assert_select "dl.instruction-list"
  end

  test "backfill creates verified Dirt entries only for years without entries" do
    ensure_dirt_position
    create_timesheet!(
      position: positions(:khaki_supervisor),
      on_duty: Time.zone.local(1998, 9, 1, 10, 0, 0),
      off_duty: Time.zone.local(1998, 9, 1, 16, 0, 0),
      review_status: Timesheet::STATUS_VERIFIED
    )
    sign_in_as(@admin)

    post backfill_person_timesheets_path(@target), params: { years: %w[1997 1998 2020] }

    created = Timesheet.for_person(@target.id).for_year(1997)
    assert_equal 1, created.count
    entry = created.first
    assert_equal Position::DIRT, entry.position_id
    assert_equal Timesheet::STATUS_VERIFIED, entry.review_status
    assert entry.suppress_duration_warning
    assert entry.timesheet_notes.where(type: TimesheetNote::TYPE_ADMIN).exists?

    # 1998 already had an entry, 2020 is outside the back fill range.
    assert_equal 1, Timesheet.for_person(@target.id).for_year(1998).count
    assert_not Timesheet.for_person(@target.id).for_year(2020).exists?
  end

  test "destroy deletes the entry and records a DELETE log" do
    sign_in_as(@timesheet_manager)

    delete person_timesheet_path(@target, @entry, year: 2026)

    assert_redirected_to person_timesheets_path(@target, year: 2026)
    assert_not Timesheet.exists?(@entry.id)
    assert TimesheetLog.where(timesheet_id: @entry.id, action: TimesheetLog::DELETE).exists?
  end

  test "edit shows the entry's own audit log" do
    sign_in_as(@timesheet_manager)
    patch person_timesheet_path(@target, @entry, year: 2026),
          params: { timesheet: { review_status: Timesheet::STATUS_VERIFIED } }

    get edit_person_timesheet_path(@target, @entry, year: 2026)

    assert_response :success
    assert_select "td", text: /Verified/
  end

  test "log page renders the audit trail" do
    sign_in_as(@timesheet_manager)
    patch person_timesheet_path(@target, @entry, year: 2026),
          params: { timesheet: { off_duty: "2026-08-28T18:00" } }

    get log_person_timesheets_path(@target, year: 2026)

    assert_response :success
    assert_select "summary", text: /Khaki Supervisor/
  end

  # A shift relink writes an update log carrying only slot_id. Without its own
  # branch the row would render as a bare "Updated" with nothing under it.
  test "log page names both ends of a shift change" do
    slot = Slot.create!(position: @entry.position, begins: @entry.on_duty,
                        ends: @entry.on_duty + 6.hours,
                        description: "Swing Shift", max: 10, active: true)
    TimesheetLog.record(TimesheetLog::UPDATE, @target.id, @timesheet_manager.id,
                        @entry.id, { slot_id: [nil, slot.id] }, @entry.on_duty.year)
    sign_in_as(@timesheet_manager)

    get log_person_timesheets_path(@target, year: 2026)

    assert_response :success
    assert_match "Shift update:", response.body
    assert_match "Swing Shift", response.body
    assert_match "No shift", response.body
  end

  test "breakdown page renders the hours and position summaries" do
    sign_in_as(@event_manager)

    get breakdown_person_timesheets_path(@target, year: 2026)

    assert_response :success
    assert_select "td", text: /Khaki Supervisor/
  end

  test "the shift manage page and its actions require the shift management role" do
    sign_in_as(@timesheet_manager)

    get person_shift_manage_path(@target)
    assert_redirected_to person_timesheets_path(@target, year: 2026)

    post start_shift_person_timesheets_path(@target),
         params: { position_id: positions(:khaki_supervisor).id }

    assert_redirected_to person_timesheets_path(@target, year: 2026)
    assert_nil Timesheet.find_person_on_duty(@target.id)
  end

  test "an admin can check the person in from the shift manage page" do
    ensure_role(Role::SHIFT_MANAGEMENT, "Shift Management")
    position = Position.create!(title: "Sunrise Patrol", active: true, no_training_required: true)
    PersonPosition.create!(person_id: @target.id, position_id: position.id)
    sign_in_as(@admin)

    # The timesheet page links to the check in/out page instead of hosting the panel.
    get person_timesheets_path(@target, year: 2026)
    assert_response :success
    assert_select "a[href=?]", person_shift_manage_path(@target), text: /Shift Check In\/Out/
    assert_select "option", text: "Sunrise Patrol", count: 0

    get person_shift_manage_path(@target)
    assert_response :success
    assert_select "option", text: "Sunrise Patrol"
    assert_select "a[href=?]", person_timesheets_path(@target, year: 2026), text: /2026 Timesheet/

    post start_shift_person_timesheets_path(@target), params: { position_id: position.id }
    assert_redirected_to person_shift_manage_path(@target)

    entry = Timesheet.find_person_on_duty(@target.id)
    assert entry
    assert TimesheetLog.where(timesheet_id: entry.id, action: TimesheetLog::SIGNON).exists?

    get person_shift_manage_path(@target)
    assert_response :success
    assert_select "#current-shift", text: /Sunrise Patrol/
  end

test "ending a shift that restores an inactive person to active opens the modal on the next page" do
  ensure_role(Role::SHIFT_MANAGEMENT, "Shift Management")
  inactive = person(:inactive_ranger)
  on_duty_entry = create_timesheet!(
    person: inactive,
    position: positions(:khaki_supervisor),
    on_duty: Time.zone.local(2026, 8, 30, 8, 0, 0),
    off_duty: nil,
    review_status: Timesheet::STATUS_UNVERIFIED
  )
  sign_in_as(@admin)

  post end_shift_person_timesheets_path(inactive), params: { entry_id: on_duty_entry.id }

  assert_redirected_to person_shift_manage_path(inactive)
  assert_equal Person::ACTIVE, inactive.reload.status
  # The conversion is not toast text any more; the modal carries it.
  assert_no_match(/Active/, flash[:success])

  follow_redirect!
  assert_response :success
  assert_select "dialog#shift-converted-modal", text: /#{inactive.callsign}.s account was Inactive/

  # Delivered once: a plain visit to the page does not open it again.
  get person_shift_manage_path(inactive)
  assert_select "dialog#shift-converted-modal", count: 0
end

  test "the entries table filters on position, and the chip that drops it keeps the year" do
    sign_in_as(@timesheet_manager)
    create_timesheet!(position: positions(:council_manager),
                      on_duty: Time.zone.local(2026, 8, 29, 10, 0, 0),
                      off_duty: Time.zone.local(2026, 8, 29, 16, 0, 0),
                      review_status: Timesheet::STATUS_VERIFIED)

    get person_timesheets_path(@target, year: 2026, position_id: positions(:council_manager).id)

    assert_response :success
    assert_select "td", text: /Council Manager/
    assert_select "td", text: /Khaki Supervisor/, count: 0
    # The chip names the position, not its id, and its remove link keeps the
    # year -- dropping it must not snap the page back to the current year.
    assert_select "span", text: "Position: Council Manager"
    assert_select "a[href=?]", person_timesheets_path(@target, year: 2026)
  end

  test "every filter choice is offered, and the ones leading nowhere are disabled" do
    sign_in_as(@timesheet_manager)

    get person_timesheets_path(@target, year: 2026)

    assert_response :success
    # The year's only entry is unverified, so that is the one status choice that
    # leads anywhere. The rest stay listed, greyed, carrying their zero -- a
    # dropped option would say nothing about what the timesheet does not hold.
    assert_select "select[name=status] option[value=?]", Timesheet::STATUS_UNVERIFIED do |option|
      assert_nil option.first["disabled"]
      assert_equal "Unverified (1)", option.first.text
    end
    assert_select "select[name=status] option[disabled][value=?]", Timesheet::STATUS_PENDING,
                  text: "Correction Requested (0)"
    assert_select "select[name=issue] option[disabled][value=?]",
                  Person::TimesheetsHelper::OVERLAPPING_FILTER
    # Every select is drawn, even one whose choices are all dead ends.
    assert_select "select[name=echelon]"
    # "All" always leads somewhere.
    assert_select "select[name=status] option[disabled][value=?]",
                  UiComponents::FilterBarHelper::ALL_FILTER, count: 0
  end

  test "a filter value the page does not offer narrows nothing and draws no chip" do
    sign_in_as(@timesheet_manager)

    # A hash parameter reaches the controller as ActionController::Parameters;
    # it must land on the sentinel rather than raising out of the chip builder.
    get person_timesheets_path(@target, year: 2026, status: "bogus", position_id: { a: "1" })

    assert_response :success
    assert_select "td", text: /Khaki Supervisor/
    assert_select "span", text: /\AStatus:/, count: 0
    assert_select "span", text: /\APosition:/, count: 0
  end

  test "the status filter tells a still on duty entry from its review status" do
    sign_in_as(@timesheet_manager)
    create_timesheet!(position: positions(:council_manager),
                      on_duty: Time.zone.local(2026, 8, 29, 10, 0, 0), off_duty: nil,
                      review_status: Timesheet::STATUS_UNVERIFIED)

    get person_timesheets_path(@target, year: 2026,
                               status: Person::TimesheetsHelper::ON_DUTY_FILTER)
    assert_select "td", text: /Council Manager/
    assert_select "td", text: /Khaki Supervisor/, count: 0

    # The same row is stored unverified, but its badge reads Still On Duty, so
    # the unverified choice must not return it.
    get person_timesheets_path(@target, year: 2026, status: Timesheet::STATUS_UNVERIFIED)
    assert_select "td", text: /Khaki Supervisor/
    assert_select "td", text: /Council Manager/, count: 0
  end

  test "the flagged filter returns exactly the entries the table warns about" do
    sign_in_as(@timesheet_manager)
    create_timesheet!(position: positions(:council_manager),
                      on_duty: Time.zone.local(2026, 8, 27, 10, 0, 0),
                      off_duty: Time.zone.local(2026, 8, 27, 10, 5, 0),
                      review_status: Timesheet::STATUS_UNVERIFIED)
    suppressed = create_timesheet!(position: positions(:mentor_manager),
                                   on_duty: Time.zone.local(2026, 8, 26, 10, 0, 0),
                                   off_duty: Time.zone.local(2026, 8, 26, 10, 5, 0),
                                   review_status: Timesheet::STATUS_UNVERIFIED)
    suppressed.update_columns(suppress_duration_warning: true)

    get person_timesheets_path(@target, year: 2026,
                               issue: Person::TimesheetsHelper::TOO_SHORT_FILTER)

    assert_response :success
    assert_select "td", text: /Council Manager/
    # Just as short, but a reviewer already dismissed the warning, so the table
    # does not flag it and neither does the filter.
    assert_select "td", text: /Mentor Team Manager/, count: 0
    assert_select "td", text: /Khaki Supervisor/, count: 0
  end

  test "the appreciation hours filter separates counting positions from the rest" do
    sign_in_as(@timesheet_manager)
    positions(:council_manager).update!(count_hours: false)
    create_timesheet!(position: positions(:council_manager),
                      on_duty: Time.zone.local(2026, 8, 29, 10, 0, 0),
                      off_duty: Time.zone.local(2026, 8, 29, 16, 0, 0),
                      review_status: Timesheet::STATUS_VERIFIED)

    get person_timesheets_path(@target, year: 2026,
                               counted: Person::TimesheetsHelper::NO_FILTER)
    assert_select "td", text: /Council Manager/
    assert_select "td", text: /Khaki Supervisor/, count: 0

    get person_timesheets_path(@target, year: 2026,
                               counted: Person::TimesheetsHelper::YES_FILTER)
    assert_select "td", text: /Khaki Supervisor/
    assert_select "td", text: /Council Manager/, count: 0
  end

  private

  def create_timesheet!(position:, on_duty:, off_duty:, review_status:, person: @target)
    entry = Timesheet.new(person_id: person.id, position_id: position.id,
                          on_duty: on_duty, off_duty: off_duty, review_status: review_status)
    entry.save!(validate: false)
    entry
  end

  def confirmation_log_count
    TimesheetLog.where(person_id: @target.id, action: TimesheetLog::CONFIRMED, timesheet_id: nil).count
  end

  def ensure_dirt_position
    return if Position.exists?(Position::DIRT)

    position = Position.new(title: "Dirt", active: true, count_hours: true, all_rangers: false,
                            new_user_eligible: false, awards_eligible: false, awards_auto_grant: false,
                            awards_grants_service_year: false)
    position.id = Position::DIRT
    position.save!
  end
end
