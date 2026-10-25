# frozen_string_literal: true

require "test_helper"

class Admin::Clubhouse1LogControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role

  setup do
    Rails.cache.clear
    Current.reset
    Clubhouse1Log.delete_all

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

  def create_log(event:, occurred: Time.zone.parse("2015-06-01 12:00:00"), user_person: nil, current_person: nil)
    Clubhouse1Log.insert!({
                            event:,
                            occurred:,
                            user_person_id: user_person&.id,
                            current_person_id: current_person&.id
                          })
    Clubhouse1Log.order(id: :desc).first
  end

  test "denies access without the admin or tech ninja role" do
    sign_in_as(@outsider)

    get admin_clubhouse1_log_path

    assert_redirected_to me_root_path
  end

  test "admin can view the index" do
    sign_in_as(@admin)

    get admin_clubhouse1_log_path

    assert_response :success
    assert_select "h1", text: /Clubhouse 1 Log/
    # The period is in the closed card; the hero keeps the years in sight.
    assert_match "from 2008 to 2019", response.body
  end

  test "tech ninja can view the index" do
    sign_in_as(@tech_ninja)

    get admin_clubhouse1_log_path

    assert_response :success
  end

  test "shows an entry with the people it names" do
    create_log(event: "=person.status active -> inactive", user_person: @actor, current_person: @subject)

    sign_in_as(@admin)

    get admin_clubhouse1_log_path

    assert_response :success
    assert_match "=person.status active -&gt; inactive", response.body
    assert_match @actor.callsign, response.body
    assert_match @subject.callsign, response.body
  end

  test "a person id naming no one reads as deleted rather than as a blank" do
    create_log(event: "#login rangers", user_person: @actor)
    Clubhouse1Log.update_all(user_person_id: 999_999)

    sign_in_as(@admin)

    get admin_clubhouse1_log_path

    assert_response :success
    assert_match "Deleted #999999", response.body
  end

  test "says so when a search matched nothing" do
    create_log(event: "#login rangers")

    sign_in_as(@admin)

    get admin_clubhouse1_log_path(filter: { event_text: "nothing matches this" })

    assert_response :success
    assert_match "No entries matched the current filters.", response.body
  end

  test "narrows the list by who acted" do
    create_log(event: "#login mine", user_person: @actor)
    create_log(event: "#login theirs", user_person: @subject)

    sign_in_as(@admin)

    get admin_clubhouse1_log_path(filter: { user_callsign: @actor.callsign })

    assert_response :success
    assert_match "#login mine", response.body
    assert_no_match "#login theirs", response.body
  end

  test "narrows the list by who was acted upon" do
    create_log(event: "=person.status mine", current_person: @subject)
    create_log(event: "=person.status theirs", current_person: @actor)

    sign_in_as(@admin)

    get admin_clubhouse1_log_path(filter: { target_callsign: @subject.callsign })

    assert_response :success
    assert_match "=person.status mine", response.body
    assert_no_match "=person.status theirs", response.body
  end

  test "reads a bare number as a person id" do
    create_log(event: "#login mine", user_person: @actor)
    create_log(event: "#login theirs", user_person: @subject)

    sign_in_as(@admin)

    get admin_clubhouse1_log_path(filter: { user_callsign: @actor.id.to_s })

    assert_response :success
    assert_match "#login mine", response.body
    assert_no_match "#login theirs", response.body
  end

  test "a callsign no one holds returns nothing rather than everything" do
    create_log(event: "#login rangers", user_person: @actor)

    sign_in_as(@admin)

    get admin_clubhouse1_log_path(filter: { user_callsign: "NotARealCallsign" })

    assert_response :success
    assert_match "No entries matched the current filters.", response.body
  end

  test "a chosen kind of entry reaches the search" do
    create_log(event: "#login rangers")
    create_log(event: "!DB 'SQL error'")

    sign_in_as(@admin)

    get admin_clubhouse1_log_path(filter: { event_categories: ["login"] })

    assert_response :success
    assert_match "#login rangers", response.body
    assert_no_match "SQL error", response.body
  end

  test "the login kind finds logins, which the first Clubhouse wrote as #login" do
    create_log(event: "#login rangers")
    create_log(event: "#logout rangers")

    sign_in_as(@admin)

    get admin_clubhouse1_log_path(filter: { event_categories: ["login"] })

    assert_response :success
    assert_match "#login rangers", response.body
    assert_match "#logout rangers", response.body
  end

  test "the kind checkboxes are named so the search actually receives them" do
    sign_in_as(@admin)

    get admin_clubhouse1_log_path

    assert_response :success
    assert_select "input[type=checkbox][name=?][value=?]", "filter[event_categories][]", "login"
  end

  test "a kind of entry no one offers is ignored rather than matching nothing" do
    create_log(event: "#login rangers")

    sign_in_as(@admin)

    get admin_clubhouse1_log_path(filter: { event_categories: ["not-a-kind"] })

    assert_response :success
    assert_match "#login rangers", response.body
  end

  test "narrows the list by the text an entry contains" do
    create_log(event: "#REQ GET timesheet:selectByCallsign")
    create_log(event: "#REQ GET dashboard:mypersonalinfo")

    sign_in_as(@admin)

    get admin_clubhouse1_log_path(filter: { event_text: "timesheet" })

    assert_response :success
    assert_match "timesheet:selectByCallsign", response.body
    assert_no_match "dashboard:mypersonalinfo", response.body
  end

  test "narrows the list by time range" do
    create_log(event: "#login inside", occurred: Time.zone.parse("2015-06-01 12:00:00"))
    create_log(event: "#login outside", occurred: Time.zone.parse("2010-06-01 12:00:00"))

    sign_in_as(@admin)

    get admin_clubhouse1_log_path(filter: { start_time: "2015-01-01 00:00:00", end_time: "2015-12-31 23:59:59" })

    assert_response :success
    assert_match "#login inside", response.body
    assert_no_match "#login outside", response.body
  end

  test "offers the next page while one follows, and no more after the last" do
    (Clubhouse1Log::PAGE_SIZE_DEFAULT + 1).times { |n| create_log(event: "#login #{n}") }

    sign_in_as(@admin)

    get admin_clubhouse1_log_path

    assert_response :success
    assert_match "Page 1", response.body
    assert_select "a", text: "Next Page"
    assert_select "a", text: "Previous Page", count: 0

    get admin_clubhouse1_log_path(filter: { page: 2 })

    assert_response :success
    assert_match "Page 2", response.body
    assert_select "a", text: "Previous Page"
    assert_select "a", text: "Next Page", count: 0
  end

  test "keeps the filters when paging" do
    create_log(event: "#login rangers")

    sign_in_as(@admin)

    get admin_clubhouse1_log_path(filter: { event_text: "login", page: 2 })

    assert_response :success
    assert_match "Page 2", response.body
    # The link itself must carry the search forward, not merely exist.
    previous = css_select("a").find { |a| a.text.strip == "Previous Page" }
    assert_includes CGI.unescape(previous["href"]), "filter[event_text]=login"
  end

  test "a filter param that is not a hash is ignored rather than raising" do
    create_log(event: "#login rangers")

    sign_in_as(@admin)

    get "/admin/clubhouse1-log?filter=x"

    assert_response :success
    assert_match "#login rangers", response.body
  end

  test "a page number past any real page does not reach the database" do
    sign_in_as(@admin)

    get admin_clubhouse1_log_path(filter: { page: "99999999999999999999" })

    assert_response :success
  end

  test "a page past the last entry offers one step back to the start" do
    create_log(event: "#login rangers")

    sign_in_as(@admin)

    get admin_clubhouse1_log_path(filter: { page: 4 })

    assert_response :success
    assert_select "a", text: "Back to the First Page"
  end

  test "an emoji in the search finds nothing rather than raising" do
    create_log(event: "#login rangers")

    sign_in_as(@admin)

    get admin_clubhouse1_log_path(filter: { event_text: "\u{1F525}" })

    assert_response :success
    assert_no_match "#login rangers", response.body
  end

  test "a callsign made only of digits finds the person who holds it" do
    numeric = person(:prospective_ranger)
    numeric.update_columns(callsign: "4748", callsign_normalized: "4748")
    mine = create_log(event: "#login mine", user_person: numeric)
    create_log(event: "#login theirs", user_person: @actor)

    sign_in_as(@admin)

    get admin_clubhouse1_log_path(filter: { user_callsign: "4748" })

    assert_response :success
    assert_match "#login mine", response.body
    assert_no_match "#login theirs", response.body
    assert_equal numeric.id, mine.user_person_id
  end

  test "a person id of zero reads as no one, not as a deleted person" do
    create_log(event: "=person.status changed", current_person: nil)
    Clubhouse1Log.update_all(current_person_id: 0)

    sign_in_as(@admin)

    get admin_clubhouse1_log_path

    assert_response :success
    assert_no_match "Deleted #0", response.body
  end

  test "a partial date is refused rather than filtering by a date no one typed" do
    create_log(event: "#login rangers", occurred: Time.zone.parse("2015-06-01 12:00:00"))

    sign_in_as(@admin)

    get admin_clubhouse1_log_path(filter: { start_time: "August" })

    assert_response :success
    assert_match "#login rangers", response.body
    assert_no_match "From:", response.body
  end

  test "a year outside the calendar is refused rather than ignored" do
    create_log(event: "#login rangers", occurred: Time.zone.parse("2015-06-01 12:00:00"))

    sign_in_as(@admin)

    get admin_clubhouse1_log_path(filter: { start_time: "99999-01-01" })

    assert_response :success
    assert_match "#login rangers", response.body
  end

  test "an unreadable time draws no chip promising a filter that was not applied" do
    create_log(event: "#login rangers")

    sign_in_as(@admin)

    get admin_clubhouse1_log_path(filter: { start_time: "garbage" })

    assert_response :success
    assert_match "#login rangers", response.body
    # The field still shows what was typed; the chip must not claim it applied.
    assert_no_match "From: garbage", response.body
  end

  test "says the log is empty when nothing is filtered" do
    sign_in_as(@admin)

    get admin_clubhouse1_log_path

    assert_response :success
    assert_match "The Clubhouse 1 Log holds no entries.", response.body
  end
end
