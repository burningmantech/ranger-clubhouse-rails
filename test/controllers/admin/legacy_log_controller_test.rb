# frozen_string_literal: true

require "test_helper"

class Admin::LegacyLogControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include EnvTestHelper

  setup do
    Rails.cache.clear
    Current.reset
    LegacyLog.delete_all

    @admin = person(:active_ranger)
    @tech_ninja = person(:echelon_ranger)
    @outsider = person(:inactive_ranger)
    @actor = person(:auditor_ranger)
    @subject = person(:retired_ranger)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::TECH_NINJA, "Tech Ninja")
    grant_role(@admin, Role::ADMIN)
    grant_role(@tech_ninja, Role::TECH_NINJA)
  end

  teardown do
    Current.reset
    Rails.cache.clear
  end

  # A row as the conversion writes it: the raw event as the message, and the
  # event, log id and target source in data, unless the test says otherwise.
  def legacy(event: "unknown", message: "=person.status=alpha@id=1", person: nil, target: nil,
             created_at: Time.zone.parse("2015-06-01 12:00:00"), data: nil)
    log_id = (LegacyLog.maximum(:log_id) || 0) + 1
    data ||= { "event" => message, "log_id" => log_id, "target_source" => "session" }
    LegacyLog.insert!({ log_id:, person_id: person&.id, target_person_id: target&.id, event:, message:, data:,
                        created_at: })
    LegacyLog.find_by!(log_id:)
  end

  test "denies access without the admin or tech ninja role" do
    sign_in_as(@outsider)

    get admin_legacy_log_path

    assert_redirected_to me_root_path
  end

  test "admin can view the index" do
    sign_in_as(@admin)

    get admin_legacy_log_path

    assert_response :success
    assert_select "h1", text: /Legacy Clubhouse 1 Log/
    assert_select "label", text: /User Callsign/
    assert_select "label", text: /Starts At/
    assert_select "label", text: /Ends At/
    assert_match "from 2008 to 2019", response.body
  end

  test "tech ninja can view the index, with callsigns as text rather than links that bounce" do
    legacy(person: @actor, target: @subject)

    sign_in_as(@tech_ninja)

    get admin_legacy_log_path

    assert_response :success
    assert_match @actor.callsign, response.body
    assert_select "a[href=?]", person_path(@actor), count: 0
  end

  test "is refused on the Groundhog Day server" do
    sign_in_as(@admin)

    with_env("RANGER_CLUBHOUSE_GROUNDHOG_DAY_TIME" => "2025-08-30 12:00") do
      get admin_legacy_log_path
    end

    assert_redirected_to me_root_path
  end

  test "shows an entry with its people, and its detail row" do
    row = legacy(person: @actor, target: @subject)

    sign_in_as(@admin)

    get admin_legacy_log_path

    assert_response :success
    assert_select "a[href=?]", person_path(@actor), text: @actor.callsign
    assert_select "a[href=?]", person_path(@subject), text: @subject.callsign
    assert_select "button[data-controller='toggle'][data-toggle-dom-id-value=?]", "legacy-log-detail-#{row.id}", count: 1
    assert_select "tr#legacy-log-detail-#{row.id}.hidden", count: 1
    assert_select "tr#legacy-log-detail-#{row.id}" do
      assert_select "pre", text: /"target_source": "session"/
      assert_select "dt", text: "Clubhouse 1 Entry"
      assert_select "dd", text: "##{row.log_id}"
      assert_select "dt", text: "Session Person", count: 0
      assert_select "dt", text: "Truncated", count: 0
    end
    assert_select "[data-controller='read-more']", count: 0
    assert_match "=person.status=alpha@id=1", response.body
  end

  test "the session person and the truncation note appear when the data carries them" do
    row = legacy(event: "person-update", message: "UPDATE person SET status=alpha WHERE id=#{@subject.id}",
                 person: @actor, target: @subject,
                 data: { "event" => "x", "log_id" => 1, "session_person_id" => @actor.id, "truncated" => true })

    sign_in_as(@admin)

    get admin_legacy_log_path

    assert_response :success
    assert_select "tr#legacy-log-detail-#{row.id}" do
      assert_select "dt", text: "Session Person"
      assert_select "dd a[href=?]", person_path(@actor), text: @actor.callsign
      assert_select "dt", text: "Truncated"
      assert_select "dd", text: /cut this statement short/
    end
  end

  test "a long message folds behind Show More" do
    legacy(message: "=person.#{"x" * 80}@id=1")

    sign_in_as(@admin)

    get admin_legacy_log_path

    assert_response :success
    assert_select "[data-controller='read-more']", count: 1
  end

  test "a person id naming no one reads as deleted rather than as a blank" do
    legacy(person: @actor)
    LegacyLog.update_all(person_id: 999_999)

    sign_in_as(@admin)

    get admin_legacy_log_path

    assert_response :success
    assert_match "Deleted #999999", response.body
  end

  test "says the conversion has not run when the table is empty" do
    sign_in_as(@admin)

    get admin_legacy_log_path

    assert_response :success
    assert_match "The conversion has not run yet.", response.body
  end

  test "says so when a search matched nothing" do
    legacy

    sign_in_as(@admin)

    get admin_legacy_log_path(filter: { message: "nothing matches this" })

    assert_response :success
    assert_match "No entries matched the current filters.", response.body
    assert_no_match "The conversion has not run yet.", response.body
  end

  test "a page past the last entry offers one step back to the start" do
    legacy

    sign_in_as(@admin)

    get admin_legacy_log_path(filter: { page: 4 })

    assert_response :success
    assert_match "There is nothing on page 4.", response.body
    assert_select "a", text: "Back to the First Page"
  end

  test "narrows the list by who acted, drawing a chip for it" do
    legacy(message: "=person.status=mine@id=1", person: @actor)
    legacy(message: "=person.status=theirs@id=1", person: @subject)

    sign_in_as(@admin)

    get admin_legacy_log_path(filter: { person_callsign: @actor.callsign })

    assert_response :success
    assert_match "=person.status=mine@id=1", response.body
    assert_no_match "=person.status=theirs@id=1", response.body
    assert_select "a[aria-label^='Remove filter: User: #{@actor.callsign}']"
  end

  test "narrows the list by who was acted upon" do
    legacy(message: "=person.status=mine@id=1", target: @subject)
    legacy(message: "=person.status=theirs@id=1", target: @actor)

    sign_in_as(@admin)

    get admin_legacy_log_path(filter: { target_person_callsign: @subject.callsign })

    assert_response :success
    assert_match "=person.status=mine@id=1", response.body
    assert_no_match "=person.status=theirs@id=1", response.body
  end

  test "reads a bare number as a person id" do
    legacy(message: "=person.status=mine@id=1", person: @actor)
    legacy(message: "=person.status=theirs@id=1", person: @subject)

    sign_in_as(@admin)

    get admin_legacy_log_path(filter: { person_callsign: @actor.id.to_s })

    assert_response :success
    assert_match "=person.status=mine@id=1", response.body
    assert_no_match "=person.status=theirs@id=1", response.body
  end

  test "a callsign no one holds returns nothing rather than everything" do
    legacy(person: @actor)

    sign_in_as(@admin)

    get admin_legacy_log_path(filter: { person_callsign: "NotARealCallsign" })

    assert_response :success
    assert_match "No entries matched the current filters.", response.body
  end

  test "a chosen category reaches the search, and draws a chip" do
    legacy(event: "unknown", message: "=person.status=raw@id=1")
    legacy(event: "person-update", message: "UPDATE person SET status=alpha WHERE id=1")

    sign_in_as(@admin)

    get admin_legacy_log_path(filter: { event_filters: ["unknown"] })

    assert_response :success
    assert_match "=person.status=raw@id=1", response.body
    assert_no_match "UPDATE person SET status=alpha WHERE id=1", response.body
    assert_select "a[aria-label^='Remove filter: Category: Unknown']"
  end

  test "the category checkboxes are named so the search actually receives them" do
    sign_in_as(@admin)

    get admin_legacy_log_path

    assert_response :success
    assert_select "input[type=checkbox][name=?][value=?]", "filter[event_filters][]", "unknown"
    assert_select "input[type=checkbox][name=?][value=?]", "filter[event_filters][]", "person-slot-%"
  end

  test "a category no one offers is ignored rather than matching nothing" do
    legacy(message: "=person.status=raw@id=1")

    sign_in_as(@admin)

    get admin_legacy_log_path(filter: { event_filters: ["not-a-category"] })

    assert_response :success
    assert_match "=person.status=raw@id=1", response.body
  end

  test "a category and an event name combine as either matching" do
    legacy(event: "unknown", message: "=person.status=raw@id=1")
    legacy(event: "person-update", message: "UPDATE person SET status=alpha WHERE id=1")
    legacy(event: "slot-create", message: "INSERT INTO slot")

    sign_in_as(@admin)

    get admin_legacy_log_path(filter: { event_filters: ["unknown"], event_name: "person-update" })

    assert_response :success
    assert_match "=person.status=raw@id=1", response.body
    assert_match "UPDATE person SET status=alpha WHERE id=1", response.body
    assert_no_match "INSERT INTO slot", response.body
  end

  test "narrows the list by time range" do
    legacy(message: "=person.status=inside@id=1", created_at: Time.zone.parse("2015-06-01 12:00:00"))
    legacy(message: "=person.status=outside@id=1", created_at: Time.zone.parse("2010-06-01 12:00:00"))

    sign_in_as(@admin)

    get admin_legacy_log_path(filter: { start_time: "2015-01-01 00:00:00", end_time: "2015-12-31 23:59:59" })

    assert_response :success
    assert_match "=person.status=inside@id=1", response.body
    assert_no_match "=person.status=outside@id=1", response.body
    assert_select "a[aria-label^='Remove filter: From: 2015-01-01 00:00']"
  end

  test "a partial date narrows nothing and draws no chip" do
    legacy(message: "=person.status=old@id=1", created_at: Time.zone.parse("2010-06-01 12:00:00"))

    sign_in_as(@admin)

    get admin_legacy_log_path(filter: { start_time: "26" })

    assert_response :success
    assert_match "=person.status=old@id=1", response.body
    assert_select "a[aria-label^='Remove filter: From']", count: 0
  end

  test "offers the next page while one follows, and carries the filters along" do
    (LegacyLog::PAGE_SIZE_DEFAULT + 1).times { |n| legacy(message: "=person.status=row#{n}@id=1") }

    sign_in_as(@admin)

    get admin_legacy_log_path(filter: { event_filters: ["unknown"] })

    assert_response :success
    assert_match "Page 1", response.body
    next_link = css_select("a").find { |a| a.text.strip == "Next Page" }
    assert_includes CGI.unescape(next_link["href"]), "filter[event_filters][]=unknown"
    assert_select "a", text: "Previous Page", count: 0

    get admin_legacy_log_path(filter: { event_filters: ["unknown"], page: 2 })

    assert_response :success
    assert_match "Page 2", response.body
    assert_select "a", text: "Previous Page"
    assert_select "a", text: "Next Page", count: 0
  end

  test "a filter param that is not a hash is ignored rather than raising" do
    legacy(message: "=person.status=raw@id=1")

    sign_in_as(@admin)

    get "/admin/legacy-log?filter=x"

    assert_response :success
    assert_match "=person.status=raw@id=1", response.body
  end

  test "a page number past any real page does not reach the database" do
    sign_in_as(@admin)

    get admin_legacy_log_path(filter: { page: "99999999999999999999" })

    assert_response :success
  end
end
