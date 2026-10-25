# frozen_string_literal: true

require "test_helper"

class Admin::EventDatesControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper

  YEAR = 2026

  setup do
    Rails.cache.clear
    EventDate.delete_all

    @admin = person(:auditor_ranger)
    @tech_ninja = person(:echelon_ranger)
    @slot_editor = person(:active_ranger)
    @outsider = person(:retired_ranger)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::TECH_NINJA, "Tech Ninja")
    ensure_role(Role::EDIT_SLOTS, "Edit Slots")

    grant_role(@admin, Role::ADMIN)
    grant_role(@tech_ninja, Role::TECH_NINJA)
    grant_role(@slot_editor, Role::EDIT_SLOTS)

    @event_date = create_event_date

    # After the fixture record, so its own audit row does not stand in for the
    # one a test is looking for.
    ActionLog.delete_all
  end

  teardown do
    Rails.cache.clear
  end

  # ---------------------------------------------------------------- index

  test "admin sees a row per record with both windows rendered" do
    create_event_date(year: YEAR - 1)

    sign_in_as(@admin)

    get admin_event_dates_path

    assert_response :success
    assert_select "h1", text: /Event Dates/
    assert_select "tbody tr", count: 2
    assert_select "td", text: /Sun Aug 30 @ 00:00 to Mon Sep 7 @ 23:59/
    # The credit period straddles New Year, so both ends carry their year.
    assert_select "td", text: /Thu Jan 1, #{YEAR} @ 01:00 to Fri Jan 1, #{YEAR + 1} @ 00:59/
  end

  test "a record with no slot window says so rather than rendering a blank cell" do
    @event_date.update_columns(pre_event_slot_start: nil, pre_event_slot_end: nil)

    sign_in_as(@admin)

    get admin_event_dates_path

    assert_response :success
    assert_select "td", text: /Not set/
  end

  test "an empty table says why it is empty" do
    EventDate.delete_all

    sign_in_as(@admin)

    get admin_event_dates_path

    assert_response :success
    assert_select "body", text: /No event dates recorded yet/
  end

  # ----------------------------------------------------------- affordances

  test "tech ninja sees the index and both editing affordances" do
    sign_in_as(@tech_ninja)

    get admin_event_dates_path

    assert_response :success
    assert_select "a[href=?]", new_admin_event_date_path
    assert_select "a[href=?]", edit_admin_event_date_path(@event_date)
  end

  test "edit slots is turned away, the same as any other non-admin non-tech-ninja role" do
    sign_in_as(@slot_editor)

    get admin_event_dates_path

    assert_redirected_to me_root_path
  end

  test "delete is offered to an admin on the edit page but not to a tech ninja" do
    sign_in_as(@admin)
    get edit_admin_event_date_path(@event_date)
    assert_response :success
    assert_select "a[href=?]", admin_event_date_path(@event_date), text: /Delete Event Date/

    sign_in_as(@tech_ninja)
    get edit_admin_event_date_path(@event_date)
    assert_response :success
    assert_select "a[href=?]", admin_event_date_path(@event_date), count: 0
  end

  test "a person with none of the three roles is turned away" do
    sign_in_as(@outsider)

    get admin_event_dates_path

    assert_redirected_to me_root_path
  end

  # --------------------------------------------------------------- writes

  test "admin creates a record and all six dates persist" do
    EventDate.delete_all

    sign_in_as(@admin)

    assert_difference "EventDate.count", 1 do
      post admin_event_dates_path, params: { event_date: valid_params }
    end

    assert_redirected_to admin_event_dates_path

    created = EventDate.last
    assert_equal Time.zone.local(YEAR, 8, 30, 0, 0, 0), created.event_start
    assert_equal Time.zone.local(YEAR, 9, 7, 23, 59, 0), created.event_end
    assert_equal Time.zone.local(YEAR, 1, 1, 1, 0, 0), created.pre_event_start
    assert_equal Time.zone.local(YEAR + 1, 1, 1, 0, 59, 0), created.post_event_end
    assert_equal Time.zone.local(YEAR, 8, 20, 0, 0, 0), created.pre_event_slot_start
    assert_equal Time.zone.local(YEAR, 8, 28, 0, 0, 0), created.pre_event_slot_end
  end

  test "admin updates a record" do
    sign_in_as(@admin)

    patch admin_event_date_path(@event_date),
          params: { event_date: valid_params(event_end: "#{YEAR}-09-08 12:00") }

    assert_redirected_to admin_event_dates_path
    assert_equal Time.zone.local(YEAR, 9, 8, 12, 0, 0), @event_date.reload.event_end
  end

  test "tech ninja updates a record" do
    sign_in_as(@tech_ninja)

    patch admin_event_date_path(@event_date),
          params: { event_date: valid_params(event_end: "#{YEAR}-09-09 12:00") }

    assert_redirected_to admin_event_dates_path
    assert_equal Time.zone.local(YEAR, 9, 9, 12, 0, 0), @event_date.reload.event_end
  end

  test "edit slots cannot create" do
    sign_in_as(@slot_editor)

    assert_no_difference "EventDate.count" do
      post admin_event_dates_path, params: { event_date: valid_params }
    end

    assert_redirected_to me_root_path
    assert_equal "You are not authorized to view the page.", flash[:error]
  end

  test "edit slots cannot update" do
    sign_in_as(@slot_editor)
    original = @event_date.event_end

    patch admin_event_date_path(@event_date),
          params: { event_date: valid_params(event_end: "#{YEAR}-09-10 12:00") }

    assert_redirected_to me_root_path
    assert_equal "You are not authorized to view the page.", flash[:error]
    assert_equal original, @event_date.reload.event_end
  end

  test "admin deletes a record" do
    sign_in_as(@admin)

    assert_difference "EventDate.count", -1 do
      delete admin_event_date_path(@event_date)
    end

    assert_redirected_to admin_event_dates_path
  end

  test "tech ninja cannot delete" do
    sign_in_as(@tech_ninja)

    assert_no_difference "EventDate.count" do
      delete admin_event_date_path(@event_date)
    end

    assert_redirected_to admin_event_dates_path
    assert_equal "You are not authorized to delete an event date.", flash[:error]
  end

  # ----------------------------------------------------------- validation

  test "a backwards event window is rejected and the form comes back" do
    sign_in_as(@admin)

    patch admin_event_date_path(@event_date),
          params: { event_date: valid_params(event_end: "#{YEAR}-08-29 00:00") }

    assert_response :unprocessable_entity
    assert_select "body", text: /Event End must be after the Event Start/
  end

  test "a date in the wrong year is rejected" do
    sign_in_as(@admin)

    patch admin_event_date_path(@event_date),
          params: { event_date: valid_params(pre_event_slot_start: "#{YEAR - 1}-08-20 00:00") }

    assert_response :unprocessable_entity
    assert_select "body", text: /same year as the Event Start/
  end

  test "a post-event end in the following January is accepted" do
    EventDate.delete_all

    sign_in_as(@admin)

    assert_difference "EventDate.count", 1 do
      post admin_event_dates_path,
           params: { event_date: valid_params(post_event_end: "#{YEAR + 1}-01-15 12:00") }
    end

    assert_redirected_to admin_event_dates_path
  end

  test "a post-event end two years out is rejected" do
    sign_in_as(@admin)

    patch admin_event_date_path(@event_date),
          params: { event_date: valid_params(post_event_end: "#{YEAR + 2}-01-01 00:59") }

    assert_response :unprocessable_entity
    assert_select "body", text: /must be in #{YEAR} or January #{YEAR + 1}/
  end

  test "a rejected form still names the stored year, not the one submitted" do
    sign_in_as(@admin)

    # Retype the whole record as a different year, with a backwards window so it
    # is rejected. The delete control on the returned page targets the stored
    # record, so it has to name that record's year and not the typed one.
    patch admin_event_date_path(@event_date), params: { event_date: {
      event_start: "#{YEAR + 1}-08-30 00:00", event_end: "#{YEAR + 1}-08-29 00:00",
      pre_event_start: "#{YEAR + 1}-01-01 01:00", post_event_end: "#{YEAR + 2}-01-01 00:59",
      pre_event_slot_start: "#{YEAR + 1}-08-20 00:00", pre_event_slot_end: "#{YEAR + 1}-08-28 00:00"
    } }

    assert_response :unprocessable_entity
    assert_select "h1", text: /Edit #{YEAR} Event Dates/
    # The confirmation rides in a data-turbo-confirm attribute, not body text.
    assert_match(/Delete the #{YEAR} event dates/, response.body)
    assert_no_match(/Delete the #{YEAR + 1} event dates/, response.body)
  end

  test "a second record for a year already recorded is rejected" do
    sign_in_as(@admin)

    assert_no_difference "EventDate.count" do
      post admin_event_dates_path, params: { event_date: valid_params }
    end

    assert_response :unprocessable_entity
    assert_select "body", text: /#{YEAR} already has an event date record/
  end

  # ---------------------------------------------------------------- audit

  test "creating a record writes an action log entry" do
    EventDate.delete_all

    sign_in_as(@admin)

    post admin_event_dates_path, params: { event_date: valid_params }

    log = ActionLog.find_by(event: "event-dates-create")
    assert_not_nil log
    assert_equal @admin.id, log.person_id
  end

  private

  def create_event_date(year: YEAR)
    EventDate.create!(
      event_start: Time.zone.local(year, 8, 30, 0, 0, 0),
      event_end: Time.zone.local(year, 9, 7, 23, 59, 0),
      pre_event_start: Time.zone.local(year, 1, 1, 1, 0, 0),
      post_event_end: Time.zone.local(year + 1, 1, 1, 0, 59, 0),
      pre_event_slot_start: Time.zone.local(year, 8, 20, 0, 0, 0),
      pre_event_slot_end: Time.zone.local(year, 8, 28, 0, 0, 0)
    )
  end

  def valid_params(overrides = {})
    {
      event_start: "#{YEAR}-08-30 00:00",
      event_end: "#{YEAR}-09-07 23:59",
      pre_event_start: "#{YEAR}-01-01 01:00",
      post_event_end: "#{YEAR + 1}-01-01 00:59",
      pre_event_slot_start: "#{YEAR}-08-20 00:00",
      pre_event_slot_end: "#{YEAR}-08-28 00:00"
    }.merge(overrides)
  end
end
