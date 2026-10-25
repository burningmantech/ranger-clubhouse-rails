# frozen_string_literal: true

require "test_helper"

class Admin::ErrorLogsControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role

  setup do
    Rails.cache.clear
    Current.reset
    ErrorLog.delete_all

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

  test "denies access without the admin or tech ninja role" do
    sign_in_as(@outsider)

    get admin_error_logs_path

    assert_redirected_to me_root_path
  end

  test "admin can view the index" do
    sign_in_as(@admin)

    get admin_error_logs_path

    assert_response :success
    assert_select "h1", text: /Error Logs/
  end

  test "tech ninja can view the index" do
    sign_in_as(@tech_ninja)

    get admin_error_logs_path

    assert_response :success
  end

  test "shows an expandable row with metadata, exception, and raw data" do
    row = ErrorLog.create!(
      error_type: "salesforce-query-exception",
      person: @actor,
      ip: "10.42.0.5",
      url: "https://example.org/vc/application-import/preview",
      user_agent: "Mozilla/5.0 Test Agent",
      data: {
        "method" => "POST",
        "exception" => {
          "message" => "Net::ReadTimeout",
          "file" => "app/lib/salesforce.rb",
          "line" => 121,
          "stacktrace" => ["app/lib/salesforce.rb:121:in `query'"]
        }
      },
      created_at: Time.zone.local(2026, 8, 17, 13, 58, 2)
    )

    sign_in_as(@admin)

    get admin_error_logs_path

    assert_response :success
    assert_select "tr#error-log-detail-#{row.id}.hidden", count: 1
    assert_select "a[href=?]", person_path(@actor), text: @actor.callsign
    assert_select "button[data-controller='toggle'][data-toggle-dom-id-value=?]", "error-log-detail-#{row.id}", count: 1
    assert_select "dt", text: /IP address/
    assert_select "dt", text: /Method/
    assert_select "dt", text: /User agent/
    assert_select "body", text: /Net::ReadTimeout/
    assert_select "body", text: /app\/lib\/salesforce\.rb:121/
    assert_select "pre", text: /query/
  end

  test "masks credential-looking keys in the raw data payload, including nested ones" do
    ErrorLog.create!(
      error_type: "lms-request-failure",
      data: {
        "parameters" => {
          "password" => "hunter2",
          "commit" => "Save",
          "auth" => { "token" => "abc123" }
        }
      },
      created_at: Time.zone.local(2026, 8, 17, 9, 0, 0)
    )

    sign_in_as(@admin)

    get admin_error_logs_path

    assert_response :success
    assert_equal 2, response.body.scan("[hidden]").count
    assert_no_match(/hunter2/, response.body)
    assert_no_match(/abc123/, response.body)
  end

  test "a malformed data column renders as unreadable instead of failing the page" do
    row = ErrorLog.create!(error_type: "legacy-entry", created_at: Time.zone.local(2026, 8, 17, 9, 0, 0))
    # Bypass the JSON coder to simulate a pre-Rails legacy row whose data
    # column never was valid JSON.
    ActiveRecord::Base.connection.execute(
      "UPDATE error_logs SET data = #{ActiveRecord::Base.connection.quote('this is not { json')} WHERE id = #{row.id}"
    )

    sign_in_as(@admin)

    get admin_error_logs_path

    assert_response :success
    assert_select "body", text: /this is not \{ json/
  end

  test "a row with no person shows a dash and a row with no ip reads as server" do
    # The ip is set so only the Person cell can produce the dash -- otherwise
    # the IP cell's own fallback satisfies the assertion on its own.
    ErrorLog.create!(
      error_type: "moodle-connect-failure",
      ip: "10.0.0.9",
      created_at: Time.zone.local(2026, 8, 16, 16, 30, 12)
    )

    sign_in_as(@admin)

    get admin_error_logs_path

    assert_response :success
    assert_select "td", text: "-", count: 1
  end

  test "a record with no ip reads as server rather than a dash" do
    ErrorLog.create!(
      error_type: "lms-request-failure",
      created_at: Time.zone.local(2026, 8, 16, 15, 0, 0)
    )

    sign_in_as(@admin)

    get admin_error_logs_path

    assert_response :success
    assert_select "td", text: "server"
  end

  test "unknown callsign returns empty results without querying" do
    # A row that WOULD be returned if the callsign short-circuit were dropped,
    # so the empty state proves the guard rather than an empty table.
    ErrorLog.create!(error_type: "would-appear-without-the-guard",
                     created_at: Time.zone.local(2026, 8, 17, 8, 0, 0))

    sign_in_as(@admin)

    get admin_error_logs_path, params: { filter: { person_callsign: "UnknownCallsign" } }

    assert_response :success
    assert_select "body", text: /No error log entries matched the current filters/
    assert_select "body", text: /would-appear-without-the-guard/, count: 0
  end

  test "filters by person callsign" do
    ErrorLog.create!(error_type: "match-me", person: @actor, created_at: Time.zone.local(2026, 8, 17, 8, 0, 0))
    ErrorLog.create!(error_type: "not-this-one", created_at: Time.zone.local(2026, 8, 17, 8, 1, 0))

    sign_in_as(@admin)

    get admin_error_logs_path, params: { filter: { person_callsign: @actor.callsign } }

    assert_response :success
    assert_select "body", text: /match-me/
    assert_select "body", text: /not-this-one/, count: 0
  end

  test "filters by error type" do
    ErrorLog.create!(error_type: "salesforce-query-exception", created_at: Time.zone.local(2026, 8, 17, 8, 0, 0))
    ErrorLog.create!(error_type: "moodle-connect-failure", created_at: Time.zone.local(2026, 8, 17, 8, 1, 0))

    sign_in_as(@admin)

    get admin_error_logs_path, params: { filter: { error_type: "salesforce-query-exception" } }

    assert_response :success
    assert_select "body", text: /salesforce-query-exception/
    assert_select "body", text: /moodle-connect-failure/, count: 0
  end

  test "filters by start and end time" do
    ErrorLog.create!(error_type: "too-early", created_at: Time.zone.local(2026, 8, 15, 8, 0, 0))
    ErrorLog.create!(error_type: "in-range", created_at: Time.zone.local(2026, 8, 17, 8, 0, 0))
    ErrorLog.create!(error_type: "too-late", created_at: Time.zone.local(2026, 8, 19, 8, 0, 0))

    sign_in_as(@admin)

    get admin_error_logs_path, params: {
      filter: { start_time: "2026-08-16 00:00", end_time: "2026-08-18 00:00" }
    }

    assert_response :success
    assert_select "body", text: /in-range/
    assert_select "body", text: /too-early/, count: 0
    assert_select "body", text: /too-late/, count: 0
  end

  test "filters to the last day" do
    ErrorLog.create!(error_type: "stale-entry", created_at: 3.days.ago)
    ErrorLog.create!(error_type: "fresh-entry", created_at: 1.hour.ago)

    sign_in_as(@admin)

    get admin_error_logs_path, params: { filter: { last_day: "1" } }

    assert_response :success
    assert_select "body", text: /fresh-entry/
    assert_select "body", text: /stale-entry/, count: 0
  end

  test "filter params persist in pager links across pages" do
    51.times do |idx|
      ErrorLog.create!(error_type: "paged-entry", created_at: Time.zone.local(2026, 8, 17, 8, 0, 0) + idx.minutes)
    end

    sign_in_as(@admin)

    get admin_error_logs_path, params: { filter: { error_type: "paged-entry" } }

    assert_response :success
    assert_select "a[href*='filter%5Berror_type%5D=paged-entry'][href*='filter%5Bpage%5D=2']", text: /Next Page/
  end

  test "a scalar data payload renders instead of breaking the page" do
    ErrorLog.create!(error_type: "legacy-scalar", data: "connection refused",
                     created_at: Time.zone.local(2026, 8, 17, 9, 0, 0))

    sign_in_as(@admin)

    get admin_error_logs_path

    assert_response :success
    assert_select "body", text: /connection refused/
  end

  test "an array data payload is masked rather than dumped raw" do
    ErrorLog.create!(error_type: "legacy-array",
                     data: [{ "password" => "hunter2" }, "plain"],
                     created_at: Time.zone.local(2026, 8, 17, 9, 5, 0))

    sign_in_as(@admin)

    get admin_error_logs_path

    assert_response :success
    assert_select "body", text: /\[hidden\]/
    assert_no_match(/hunter2/, response.body)
  end

  test "a url query string is masked in both the table and the detail row" do
    ErrorLog.create!(error_type: "auth-exception",
                     url: "https://example.org/sessions/reset-token?token=SECRETTOKEN&who=fire",
                     created_at: Time.zone.local(2026, 8, 17, 9, 10, 0))

    sign_in_as(@admin)

    get admin_error_logs_path

    assert_response :success
    assert_no_match(/SECRETTOKEN/, response.body)
    assert_select "body", text: /who=fire/
  end

  test "a non-hash filter param is ignored rather than raising" do
    sign_in_as(@admin)

    get admin_error_logs_path, params: { filter: "x" }
    assert_response :success

    get admin_error_logs_path, params: { filter: ["a", "b"] }
    assert_response :success
  end

  test "a multiparameter filter key is dropped rather than raising" do
    sign_in_as(@admin)

    get admin_error_logs_path, params: { filter: { "start_time(1i)" => "2020", "page(1i)" => "2" } }

    assert_response :success
  end

  test "an absurd page number is clamped instead of overflowing the query" do
    sign_in_as(@admin)

    get admin_error_logs_path, params: { filter: { page: "99999999999999999999" } }

    assert_response :success
  end

  test "a date that cannot be read applies no filter and draws no chip" do
    ErrorLog.create!(error_type: "still-listed", created_at: Time.zone.local(2026, 8, 17, 8, 0, 0))

    sign_in_as(@admin)

    get admin_error_logs_path, params: { filter: { start_time: "2026" } }

    assert_response :success
    assert_select "body", text: /still-listed/
    assert_select "body", text: /From: 2026/, count: 0
  end

  test "the pager and purge stay reachable when a filter empties the table" do
    ErrorLog.create!(error_type: "present-but-filtered-out",
                     created_at: Time.zone.local(2026, 8, 17, 8, 0, 0))

    sign_in_as(@admin)

    get admin_error_logs_path, params: { filter: { error_type: "matches-nothing" } }

    assert_response :success
    assert_select "body", text: /No error log entries matched the current filters/
    assert_select "a[href=?]", admin_purge_error_logs_path
  end

  test "purge deletes every entry and records an audit line" do
    ErrorLog.create!(error_type: "to-be-purged", created_at: Time.zone.local(2026, 8, 17, 8, 0, 0))
    ErrorLog.create!(error_type: "also-purged", created_at: Time.zone.local(2026, 8, 17, 8, 1, 0))

    sign_in_as(@admin)

    delete admin_purge_error_logs_path

    assert_redirected_to admin_error_logs_path
    assert_equal 0, ErrorLog.count
    assert ActionLog.exists?(event: "error-log-purge")
  end

  test "tech ninja can purge" do
    ErrorLog.create!(error_type: "to-be-purged", created_at: Time.zone.local(2026, 8, 17, 8, 0, 0))

    sign_in_as(@tech_ninja)

    delete admin_purge_error_logs_path

    assert_redirected_to admin_error_logs_path
    assert_equal 0, ErrorLog.count
  end

  test "non-admin cannot purge" do
    sign_in_as(@outsider)

    delete admin_purge_error_logs_path

    assert_redirected_to me_root_path
  end
end
