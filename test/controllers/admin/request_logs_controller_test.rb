# frozen_string_literal: true

require "test_helper"

class Admin::RequestLogsControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role

  setup do
    Rails.cache.clear
    Current.reset
    RequestLog.delete_all

    @admin = person(:active_ranger)
    @tech_ninja = person(:echelon_ranger)
    @outsider = person(:inactive_ranger)
    @actor = person(:auditor_ranger)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::TECH_NINJA, "Tech Ninja")
    grant_role(@admin, Role::ADMIN)
    grant_role(@tech_ninja, Role::TECH_NINJA)
  end

  teardown do
    Current.reset
    Rails.cache.clear
  end

  def create_log(**attributes)
    RequestLog.create!({
      person: nil,
      ips: "10.0.0.1",
      url: "me/dashboard",
      status: 200,
      method: "GET",
      response_size: 100,
      completion_time: 1.5,
      created_at: Time.zone.parse("2026-08-01 10:00:00")
    }.merge(attributes))
  end

  test "denies access without the admin or tech ninja role" do
    sign_in_as(@outsider)

    get admin_request_logs_path

    assert_redirected_to me_root_path
  end

  test "admin can view the index" do
    sign_in_as(@admin)

    get admin_request_logs_path

    assert_response :success
    assert_select "h1", text: /Request Log/
    # The showing mode says so in its name, and both buttons opt out of the
    # page's active-links controller, which would mark both current.
    assert_select "a[href=?][data-active-ignore]", admin_request_logs_path, text: /Search\s*\(current view\)/
    assert_select "a[href=?][data-active-ignore]", admin_request_logs_path(mode: "live"), text: "Live"
  end

  test "tech ninja can view the index" do
    sign_in_as(@tech_ninja)

    get admin_request_logs_path

    assert_response :success
  end

  test "shows a recorded request and the detail it opens into" do
    log = create_log(person: @actor, status: 422, method: "POST", url: "me/profile",
                     ips: "203.0.113.9, 198.51.100.7",
                     request_payload: '{"callsign":"Bumblebee"}')

    sign_in_as(@admin)

    get admin_request_logs_path

    assert_response :success
    assert_select "##{"request-log-detail-#{log.id}"}"
    assert_select "td", text: /me\/profile/
    assert_match "198.51.100.7", response.body
    assert_match "Bumblebee", response.body
  end

  test "live mode shows the newest rows, the feed's template, and the logging-off notice" do
    older = create_log(url: "me/dashboard")
    newest = create_log(url: "me/schedule", status: 302)

    sign_in_as(@admin)

    get admin_request_logs_path(mode: "live")

    assert_response :success
    assert_select "[data-controller=live-log][data-live-log-cap-value=?]",
                  Admin::RequestLogsHelper::REQUEST_LOG_LIVE_CAP.to_s do
      # The stream source waits in a template until the tab is showing.
      assert_select "template[data-live-log-target=source] turbo-cable-stream-source[channel=RequestLogLiveChannel]"
      assert_select "tbody#request-log-live-rows[data-live-log-target=rows]" do
        assert_select "tr#request-log-live-#{newest.id} td", text: /me\/schedule/
        assert_select "tr#request-log-live-#{older.id}"
      end
      assert_select "[data-live-log-target=table]:not([hidden])"
      assert_select "[data-live-log-target=empty][hidden]"
      assert_select "[data-live-log-target=stalled][hidden]", text: /Live updates have stopped/
    end
    assert_select "meta[name=turbo-cache-control][content=no-cache]"
    assert_select "a[href=?]", admin_request_logs_path(mode: "live"), text: /Live\s*\(current view\)/
    assert_select "a[href=?][aria-current]", admin_request_logs_path(mode: "live"), false
    assert_match "Request logging is off", response.body
    assert_select "#request-log-filters", false
  end

  test "live mode with logging on and nothing recorded shows the empty state" do
    Setting.where(name: Setting::REQUEST_LOG_ENABLED).delete_all
    Setting.create!(name: Setting::REQUEST_LOG_ENABLED, value: "true")
    sign_in_as(@admin)

    get admin_request_logs_path(mode: "live")

    assert_response :success
    assert_no_match "Request logging is off", response.body
    assert_select "[data-live-log-target=empty]:not([hidden])", text: /No requests have been recorded yet/
    assert_select "[data-live-log-target=table][hidden]"
  end

  test "says so when nothing has been recorded" do
    sign_in_as(@admin)

    get admin_request_logs_path

    assert_response :success
    assert_match "No requests have been recorded yet.", response.body
  end

  test "narrows the list by status range" do
    rejected = create_log(status: 422, url: "me/profile")
    succeeded = create_log(status: 200, url: "me/dashboard")

    sign_in_as(@admin)

    get admin_request_logs_path(filter: { status_class: "4xx" })

    assert_response :success
    assert_select "#request-log-detail-#{rejected.id}"
    assert_select "#request-log-detail-#{succeeded.id}", false
  end

  test "narrows the list by callsign" do
    mine = create_log(person: @actor)
    other = create_log(person: @outsider)

    sign_in_as(@admin)

    get admin_request_logs_path(filter: { person_callsign: @actor.callsign })

    assert_response :success
    assert_select "#request-log-detail-#{mine.id}"
    assert_select "#request-log-detail-#{other.id}", false
  end

  test "reads a bare number as a person id" do
    mine = create_log(person: @actor)
    create_log(person: @outsider)

    sign_in_as(@admin)

    get admin_request_logs_path(filter: { person_callsign: @actor.id.to_s })

    assert_response :success
    assert_select "#request-log-detail-#{mine.id}"
  end

  test "a callsign no one holds returns nothing rather than everything" do
    create_log(person: @actor)

    sign_in_as(@admin)

    get admin_request_logs_path(filter: { person_callsign: "NotARealCallsign" })

    assert_response :success
    # A search past the window finds nothing for that reason alone, so the
    # empty state says how far back the log goes.
    assert_match "No requests matched the current filters. " \
                 "Only the last #{RequestLog::EXPIRE_DAYS_DEFAULT} days are kept.", response.body
  end

  test "ignores a filter parameter that is not a hash" do
    create_log

    sign_in_as(@admin)

    get admin_request_logs_path(filter: "nonsense")

    assert_response :success
  end

  test "expire removes records past the window and reports what it did" do
    old = create_log(created_at: 30.days.ago)
    recent = create_log(created_at: 1.hour.ago)

    sign_in_as(@admin)

    delete expire_admin_request_logs_path

    assert_redirected_to admin_request_logs_path
    assert_equal "1 request log entry deleted.", flash[:notice]
    assert_not RequestLog.exists?(old.id)
    assert RequestLog.exists?(recent.id)
  end

  test "expire is closed to a role without access" do
    log = create_log(created_at: 30.days.ago)

    sign_in_as(@outsider)

    delete expire_admin_request_logs_path

    assert_redirected_to me_root_path
    assert RequestLog.exists?(log.id)
  end
end
