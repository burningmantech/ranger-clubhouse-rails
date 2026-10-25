# frozen_string_literal: true

require "test_helper"

class AutocompleteControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper

  setup do
    @person = person(:active_ranger)
    ensure_role(Role::EVENT_MANAGEMENT, "Event Management")
    grant_role(@person, Role::EVENT_MANAGEMENT)
    sign_in_as(@person)
  end

  test "answers 401 when signed out, and remembers no page to return to" do
    sign_out
    get autocomplete_search_url, params: { q: "test", mode: "person_manage" }
    assert_response :unauthorized
    assert_nil session[:return_to_after_authenticating]
  end

  test "requires event management" do
    sign_in_as(person(:auditor_ranger))
    get autocomplete_search_url, params: { q: "TestRanger", mode: "person_manage" }, as: :json
    assert_redirected_to me_root_path
  end

  test "event management on playa is allowed while the on-playa setting is on" do
    Setting.find_or_initialize_by(name: Setting::EVENT_MANAGEMENT_ON_PLAYA_ENABLED).update!(value: "true")
    ensure_role(Role::EVENT_MANAGEMENT_ON_PLAYA, "Event Management On Playa")
    emop = person(:auditor_ranger)
    grant_role(emop, Role::EVENT_MANAGEMENT_ON_PLAYA)
    sign_in_as(emop)

    get autocomplete_search_url, params: { q: "TestRanger", mode: "person_manage" }, as: :json
    assert_response :success
  end

  test "returns JSON response format" do
    get autocomplete_search_url, params: { q: "test", mode: "person_manage" }, as: :json
    assert_response :success

    json = JSON.parse(response.body)
    assert json.key?("request_id")
    assert json.key?("query")
    assert json.key?("mode")
    assert json.key?("filters")
    assert json.key?("groups")
    assert json.key?("flat_item_ids")
    assert json.key?("items")
    assert json.key?("meta")
  end

  test "echoes query and mode in response" do
    get autocomplete_search_url, params: { q: "ranger", mode: "hq" }, as: :json
    assert_response :success

    json = JSON.parse(response.body)
    assert_equal "ranger", json["query"]
    assert_equal "hq", json["mode"]
  end

  test "returns empty results for short queries" do
    get autocomplete_search_url, params: { q: "a", mode: "person_manage" }, as: :json
    assert_response :success

    json = JSON.parse(response.body)
    assert_equal 0, json["meta"]["result_count"]
    assert_equal [], json["items"]
    assert_includes json["empty_text"], "2 characters"
  end

  test "returns empty results for blank query" do
    get autocomplete_search_url, params: { q: "", mode: "person_manage" }, as: :json
    assert_response :success

    json = JSON.parse(response.body)
    assert_equal 0, json["meta"]["result_count"]
  end

  test "defaults mode to person_manage when not provided" do
    get autocomplete_search_url, params: { q: "test" }, as: :json
    assert_response :success

    json = JSON.parse(response.body)
    assert_equal "person_manage", json["mode"]
  end

  test "clamps limit to valid range" do
    get autocomplete_search_url, params: { q: "test", mode: "person_manage", limit: 100 }, as: :json
    assert_response :success
    # Should not error even with high limit (clamped to 25)
  end

  test "clamps limit minimum to 1" do
    get autocomplete_search_url, params: { q: "test", mode: "person_manage", limit: 0 }, as: :json
    assert_response :success
    # Should not error even with zero limit (clamped to 1)
  end

  test "returns results for valid search" do
    get autocomplete_search_url, params: { q: "TestRanger", mode: "person_manage" }, as: :json
    assert_response :success

    json = JSON.parse(response.body)
    # active_ranger (callsign "TestRanger") deterministically matches — assert the hit
    # unconditionally rather than the old `> 0 || empty_text.present?` tautology.
    assert_operator json["meta"]["result_count"], :>, 0
    assert_includes json["items"].map { |i| i["meta"]["callsign"] }, "TestRanger"
  end

  test "items contain required fields" do
    get autocomplete_search_url, params: { q: "TestRanger", mode: "person_manage" }, as: :json
    assert_response :success

    json = JSON.parse(response.body)
    # TestRanger always matches, so this is unconditional (was a vacuous guard).
    assert json["items"].any?, "TestRanger must match the active_ranger fixture"
    item = json["items"].first
    assert item.key?("id")
    assert item.key?("value")
    assert item.key?("label")
    assert item.key?("html")
  end

  test "generates unique request_id" do
    get autocomplete_search_url, params: { q: "test", mode: "person_manage" }, as: :json
    json1 = JSON.parse(response.body)

    get autocomplete_search_url, params: { q: "test", mode: "person_manage" }, as: :json
    json2 = JSON.parse(response.body)

    assert_not_equal json1["request_id"], json2["request_id"]
  end

  test "returns 200 with empty payload for +id miss (RecordNotFound)" do
    get autocomplete_search_url, params: { q: "+999999", mode: "person_manage" }, as: :json
    assert_response :success

    json = JSON.parse(response.body)
    assert_equal 0, json["meta"]["result_count"]
    assert_equal [], json["items"]
    assert_equal "No person found with that record number", json["empty_text"]
  end

  test "accepts filters param without error" do
    filters = { "status_group" => "active_current" }.to_json
    get autocomplete_search_url, params: { q: "TestRanger", mode: "person_manage", filters: }, as: :json
    assert_response :success

    json = JSON.parse(response.body)
    assert json.key?("items")
    assert json.key?("meta")
  end

  test "handles malformed filters param gracefully" do
    get autocomplete_search_url, params: { q: "test", mode: "person_manage", filters: "not-json" }, as: :json
    assert_response :success
  end

  test "handles JSON array filters without crashing" do
    filters = ["status_group", "active_current"].to_json
    get autocomplete_search_url, params: { q: "TestRanger", mode: "person_manage", filters: }, as: :json
    assert_response :success

    json = JSON.parse(response.body)
    assert json.key?("items")
    assert json.key?("meta")
  end

  test "last: field-tag returns a scoped search bucketed into status categories" do
    get autocomplete_search_url, params: { q: "last:Ranger", mode: "person_manage" }, as: :json
    assert_response :success

    json = JSON.parse(response.body)
    # last_name "Ranger" matches active_ranger + retired_ranger -> deterministic hits.
    assert_operator json["meta"]["result_count"], :>, 0
    # A field-tag search preserves status grouping (it scopes the field but still buckets
    # matches into status categories with real chip counts, like the default search). The
    # default shown category is Active/Current -> a single "active_current" group, never a
    # flat "last" group. Pinned by person_adapter_test.rb
    # ("field-tag search is grouped into status categories with counted chips").
    assert json["groups"].any?, "a scoped field-tag search with hits must produce a group"
    assert(json["groups"].all? { |g| g["key"] == "active_current" })
  end

  test "field-tag below min length after strip returns empty" do
    get autocomplete_search_url, params: { q: "last:R", mode: "person_manage" }, as: :json
    assert_response :success

    json = JSON.parse(response.body)
    assert_equal 0, json["meta"]["result_count"]
  end

  test "response includes a status-group banner when grouped" do
    get autocomplete_search_url, params: { q: "TestRanger", mode: "person_manage" }, as: :json
    assert_response :success

    json = JSON.parse(response.body)
    assert json.key?("banner")
    # TestRanger deterministically matches one Active/Current person -> single-category
    # banner. Unconditional (was gated on result_count.positive?).
    assert_operator json["meta"]["result_count"], :>, 0
    assert_match(/status\(es\)/, json["banner"])
  end

  test "filtered response still includes filter definitions" do
    filters = { "status_group" => "active_current" }.to_json
    get autocomplete_search_url, params: { q: "TestRanger", mode: "person_manage", filters: }, as: :json
    assert_response :success

    json = JSON.parse(response.body)
    assert json["filters"].is_a?(Array), "filters should be present in filtered response"
    assert json["filters"].length > 0, "filters should not be empty for person_manage mode"
    assert_equal "status_group", json["filters"].first["key"]
  end

  test "email search returns results with no status chips for a permitted viewer" do
    grant_view_email(@person)
    target = person(:active_ranger)

    get autocomplete_search_url, params: { q: target.email, mode: "person_manage" }, as: :json
    assert_response :success

    json = JSON.parse(response.body)
    # An email query is status-agnostic: a flat Email list, no chip bar and no
    # multi-category banner.
    assert_equal [], json["filters"], "an email search must never carry status chips"
    assert_not_equal "Multiple status categories found", json["banner"],
                     "an email search must not render the multi-category banner"
    assert_operator json["meta"]["result_count"], :>=, 1
  end

  # -------------------------------------------------------------------------
  # Prefix dispatch: "!" -> vehicle, "#" -> asset, default -> person.
  # -------------------------------------------------------------------------

  test "! prefix dispatches to the vehicle adapter" do
    get autocomplete_search_url, params: { q: "!RANGER1", mode: "vehicle" }, as: :json
    assert_response :success

    json = JSON.parse(response.body)
    assert_operator json["meta"]["result_count"], :>, 0
    assert(json["groups"].all? { |g| g["key"] == "vehicle" })
    assert(json["items"].all? { |i| i["id"].start_with?("v") })
  end

  test "# prefix dispatches to the asset adapter and survives URL encoding into params[:q]" do
    # "#" is a fragment delimiter in URLs; sending it as an explicit param value keeps
    # it literal in params[:q] for first-char dispatch.
    get autocomplete_search_url, params: { q: "#RANGER1", mode: "asset" }, as: :json
    assert_response :success

    json = JSON.parse(response.body)
    assert_equal "#RANGER1", json["query"]
    assert_operator json["meta"]["result_count"], :>, 0
    assert(json["groups"].all? { |g| g["key"] == "asset" })
    assert(json["items"].all? { |i| i["id"].start_with?("a") })
  end

  test "vehicle empty result carries year-specific empty_text" do
    get autocomplete_search_url, params: { q: "!ZZZZZZ", mode: "vehicle" }, as: :json
    assert_response :success

    json = JSON.parse(response.body)
    assert_equal 0, json["meta"]["result_count"]
    assert_equal "No vehicles found for the #{Current.year} event.", json["empty_text"]
  end

  test "asset empty result carries year-specific empty_text" do
    get autocomplete_search_url, params: { q: "#NOPE:2024", mode: "asset" }, as: :json
    assert_response :success

    json = JSON.parse(response.body)
    assert_equal 0, json["meta"]["result_count"]
    assert_equal "No assets found for the 2024 event.", json["empty_text"]
  end

  # D2 GUARD (controller level): a callsign-colliding person must never appear in a
  # vehicle or asset search response.
  test "D2 guard: vehicle search never returns a colliding person" do
    collision = person(:plate_collision_ranger)
    get autocomplete_search_url, params: { q: "!RANGER1", mode: "vehicle" }, as: :json
    assert_response :success

    json = JSON.parse(response.body)
    record_ids = json["items"].map { |i| i["meta"]["id"] }
    assert_not_includes record_ids, collision.id
    assert(json["items"].all? { |i| i["id"].start_with?("v") })
  end

  test "D2 guard: asset search never returns a colliding person" do
    collision = person(:plate_collision_ranger)
    get autocomplete_search_url, params: { q: "#RANGER1", mode: "asset" }, as: :json
    assert_response :success

    json = JSON.parse(response.body)
    record_ids = json["items"].map { |i| i["meta"]["id"] }
    assert_not_includes record_ids, collision.id
    assert(json["items"].all? { |i| i["id"].start_with?("a") })
  end

  # -------------------------------------------------------------------------
  # HQ Window mode. Gated exactly like the HQ Window pages themselves: the
  # HQWindowInterfaceEnabled setting (defaults on) AND Admin/Shift Management.
  # A crafted mode=hq request from anyone else must be short-circuited to an
  # inert empty response and never reach the person adapter.
  # -------------------------------------------------------------------------

  test "mode=hq is inert for a viewer without the HQ window roles" do
    # "TestRanger" matches the active_ranger fixture in person_manage mode, so a
    # non-empty result here would prove the request reached the person adapter.
    get autocomplete_search_url, params: { q: "TestRanger", mode: "hq" }, as: :json
    assert_response :success

    json = JSON.parse(response.body)
    assert_equal "hq", json["mode"], "the hq mode is echoed back unchanged"
    assert_equal 0, json["meta"]["result_count"]
    assert_equal [], json["items"]
    assert_equal [], json["groups"]
    assert_equal "HQ search is not available", json["empty_text"]
  end

  test "mode=hq is inert for an unauthorized +id lookup that would otherwise hit a person" do
    target = person(:active_ranger)
    get autocomplete_search_url, params: { q: "+#{target.id}", mode: "hq" }, as: :json
    assert_response :success

    json = JSON.parse(response.body)
    assert_equal [], json["items"], "hq must not resolve a person record"
    assert_equal "HQ search is not available", json["empty_text"]
  end

  test "mode=hq is inert when the HQ Window Interface setting is off" do
    grant_hq_window(@person)
    Setting.find_or_create_by(name: Setting::HQ_WINDOW_INTERFACE_ENABLED).update!(value: "false")

    get autocomplete_search_url, params: { q: "TestRanger", mode: "hq" }, as: :json
    assert_response :success

    json = JSON.parse(response.body)
    assert_equal 0, json["meta"]["result_count"]
    assert_equal "HQ search is not available", json["empty_text"]
  end

  test "mode=hq callsign matches navigate to the HQ Window shell" do
    grant_hq_window(@person)
    target = person(:active_ranger)

    get autocomplete_search_url, params: { q: "TestRanger", mode: "hq" }, as: :json
    assert_response :success

    json = JSON.parse(response.body)
    assert_operator json["meta"]["result_count"], :>, 0
    assert_includes json["items"].map { |i| i["url"] }, hq_path(target.id)
    assert(json["items"].all? { |i| i["url"].start_with?("/hq/") },
           "every hq-mode person result must navigate to /hq/N")
    # HQ mode is a flat callsign-only search: no status chip bar, one callsign group.
    assert_equal [], json["filters"]
    assert(json["groups"].all? { |g| g["key"] == "callsign" })
  end

  test "mode=hq +id lookup navigates to the HQ Window shell" do
    grant_hq_window(@person)
    target = person(:active_ranger)

    get autocomplete_search_url, params: { q: "+#{target.id}", mode: "hq" }, as: :json
    assert_response :success

    json = JSON.parse(response.body)
    assert_equal 1, json["meta"]["result_count"]
    assert_equal hq_path(target.id), json["items"].first["url"]
  end

  test "mode=hq restricts matches to HQ-eligible statuses" do
    grant_hq_window(@person)

    # retired_ranger ("RetiredRanger") is outside PersonAdapter::HQ_STATUSES.
    get autocomplete_search_url, params: { q: "RetiredRanger", mode: "hq" }, as: :json
    assert_response :success

    json = JSON.parse(response.body)
    assert_equal 0, json["meta"]["result_count"], "a retired person must not match in hq mode"
    assert_equal "No callsigns matched", json["empty_text"]

    # Sanity contrast: the same query matches in person_manage mode.
    get autocomplete_search_url, params: { q: "RetiredRanger", mode: "person_manage" }, as: :json
    json = JSON.parse(response.body)
    assert_operator json["meta"]["result_count"], :>, 0
  end

  private

  # Grant VIEW_EMAIL to a person and purge the role cache so the next request rebuilds
  # Current.roles_manager from the DB with email-view permission. Mirrors the role-grant
  # pattern in test/controllers/person_controller_test.rb.
  def grant_view_email(person)
    role = Role.find_or_initialize_by(id: Role::VIEW_EMAIL)
    role.title = "View Email"
    role.new_user_eligible = false
    role.save!

    PersonRole.find_or_create_by!(person_id: person.id, role_id: Role::VIEW_EMAIL)
    RoleManager.purge_person(person.id.to_s)
  end

  # Grant SHIFT_MANAGEMENT so the next request qualifies for the HQ Window search
  # mode (the HQWindowInterfaceEnabled setting defaults to on).
  # ---------------------------------------------------------------------------
  # Timesheet / Swag modes: the same person search, a different destination.
  # ---------------------------------------------------------------------------

  test "mode=timesheet person matches navigate to the person timesheets page" do
    ensure_role(Role::TIMESHEET_MANAGEMENT, "Timesheet Management")
    grant_role(@person, Role::TIMESHEET_MANAGEMENT)
    target = person(:active_ranger)

    get autocomplete_search_url, params: { q: "TestRanger", mode: "timesheet" }, as: :json
    assert_response :success

    json = JSON.parse(response.body)
    assert_operator json["meta"]["result_count"], :>, 0
    assert_includes json["items"].map { |i| i["url"] }, "/person/#{target.id}/timesheets"
    assert(json["items"].all? { |i| i["url"].end_with?("/timesheets") },
           "every timesheet-mode person result must navigate to the timesheets page")
    # Same status-grouped search as person_manage, so the chip bar survives.
    assert_not_equal [], json["filters"]
  end

  test "mode=swag person matches navigate to the person swag page" do
    ensure_role(Role::QUARTERMASTER, "Quartermaster")
    grant_role(@person, Role::QUARTERMASTER)
    target = person(:active_ranger)

    get autocomplete_search_url, params: { q: "TestRanger", mode: "swag" }, as: :json
    assert_response :success

    json = JSON.parse(response.body)
    assert_operator json["meta"]["result_count"], :>, 0
    assert_includes json["items"].map { |i| i["url"] }, "/person/#{target.id}/swag"
  end

  test "a crafted mode the viewer cannot use keeps the person-manage destination" do
    target = person(:active_ranger)

    get autocomplete_search_url, params: { q: "TestRanger", mode: "swag" }, as: :json
    assert_response :success

    json = JSON.parse(response.body)
    assert_operator json["meta"]["result_count"], :>, 0
    assert_includes json["items"].map { |i| i["url"] }, "/person/#{target.id}"
    assert(json["items"].none? { |i| i["url"].include?("/swag") },
           "a viewer without Quartermaster must not be routed to the swag page")
  end

  def grant_hq_window(person)
    ensure_role(Role::SHIFT_MANAGEMENT, "Shift Management")
    grant_role(person, Role::SHIFT_MANAGEMENT)
  end
end
