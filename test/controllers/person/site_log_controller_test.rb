# frozen_string_literal: true

require "test_helper"

class Person::SiteLogControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include DomIdTestHelper
  include TimesheetAdminTestHelper
  include ReportCardTestHelper # assert_report_card

  setup do
    Rails.cache.clear
    Current.reset

    @target = person(:active_ranger)
    @manager = person(:echelon_ranger)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::MENTOR, "Mentor")
    ensure_role(Role::EVENT_MANAGEMENT, "Event Management")
    ensure_role(Role::EVENT_MANAGEMENT_ON_PLAYA, "Event Management On Playa")
    grant_role(@manager, Role::EVENT_MANAGEMENT)

    # No fixtures: the history under test is built here, oldest first.
    on_site_row(PersonOnSite::ON_SITE, @manager.id, Time.zone.local(2025, 8, 23, 11, 49))
    @left = on_site_row(PersonOnSite::OFF_SITE, nil, Time.zone.local(2025, 9, 4, 19, 5))
  end

  teardown do
    Current.reset
    Rails.cache.clear
  end

  # --- Access -------------------------------------------------------------------

  test "event management sees the history, newest first, with who marked each change" do
    sign_in_as(@manager)

    get person_site_log_path(@target)

    assert_response :success
    rows = table_rows
    assert_equal 2, rows.size
    assert_match(/Off Site.*System/, rows.first)
    assert_match(/On Site.*#{@manager.callsign}/, rows.second)
    assert_select "tbody a[href=?]", person_path(@manager), text: @manager.callsign
    assert_report_card
    assert_select "a[href=?]", person_site_log_path(@target), text: /Site Log/
  end

  test "event management on playa can open it while the on-playa setting is on" do
    Setting.find_or_initialize_by(name: Setting::EVENT_MANAGEMENT_ON_PLAYA_ENABLED).update!(value: "true")
    emop = person(:retired_ranger)
    grant_role(emop, Role::EVENT_MANAGEMENT_ON_PLAYA)
    sign_in_as(emop)

    get person_site_log_path(@target)

    assert_response :success
  end

  test "admin can open it" do
    admin = person(:auditor_ranger)
    grant_role(admin, Role::ADMIN)
    sign_in_as(admin)

    get person_site_log_path(@target)

    assert_response :success
  end

  # A Mentor passes PersonConcern's broad gate, which this page replaces.
  test "a mentor is turned away" do
    mentor = person(:ranger_with_custom_gender)
    grant_role(mentor, Role::MENTOR)
    sign_in_as(mentor)

    get person_site_log_path(@target)

    assert_redirected_to me_root_path
    assert_equal "Admin or Event Management permission is required to view the site log.", flash[:error]
  end

  test "a signed-out visitor is sent to log in" do
    get person_site_log_path(@target)

    assert_redirected_to root_path
  end

  # --- Rows ---------------------------------------------------------------------

  test "changes made in the same second keep the order they were made in" do
    on_site_row(PersonOnSite::ON_SITE, @manager.id, @left.created_at)
    sign_in_as(@manager)

    get person_site_log_path(@target)

    assert_match(/On Site/, table_rows.first)
    assert_match(/Off Site/, table_rows.second)
  end

  test "a creator whose account is gone reads as deleted" do
    gone = Person.maximum(:id) + 1
    on_site_row(PersonOnSite::ON_SITE, gone, Time.zone.local(2025, 9, 10, 9, 0))
    sign_in_as(@manager)

    get person_site_log_path(@target)

    assert_match(/Deleted ##{gone}/, table_rows.first)
    assert_includes creator_options, "Deleted ##{gone} (1)"
  end

  # January, when Pacific and Phoenix disagree: a timestamp read as a Pacific
  # wall clock hovers an hour late.
  test "the when cell's hover names the time the cell shows, winter included" do
    on_site_row(PersonOnSite::ON_SITE, @manager.id, Time.zone.local(2026, 1, 6, 14, 30))
    sign_in_as(@manager)

    get person_site_log_path(@target)

    assert_select "tbody tr:first-child span[title=?]", "Tue Jan 6, 2026 @ 14:30 (MST)",
                  text: "Tue Jan 6, 2026 @ 14:30"
  end

  # Each year is its own section, in the order the rows have, and the off-site
  # mark that ends a stay says how long it was: 2025's pair spans 12 days and
  # 7 hours. An on-site mark has no span of its own.
  test "rows are grouped by year, and an off-site mark says how long the stay was" do
    on_site_row(PersonOnSite::ON_SITE, @manager.id, Time.zone.local(2024, 8, 25, 10, 0))
    on_site_row(PersonOnSite::OFF_SITE, @manager.id, Time.zone.local(2024, 9, 3, 16, 30))
    sign_in_as(@manager)

    get person_site_log_path(@target)

    assert_equal %w[2025 2024], year_headings
    rows = table_rows
    assert_equal 4, rows.size
    assert_match(/Off Site 12 days 7 hours System/, rows[0])
    assert_match(/On Site — #{@manager.callsign}/, rows[1])
    assert_match(/Off Site 9 days 6 hours/, rows[2])
    assert_select "th", text: "Duration", count: 2

    get person_site_log_path(@target, filter: { sort: "asc" })

    assert_equal %w[2024 2025], year_headings

    # The pairing reads the whole history, so hiding the on-site marks keeps the spans.
    get person_site_log_path(@target, filter: { marked: PersonOnSite::OFF_SITE })

    assert_match(/12 days 7 hours/, table_rows.first)
  end

  test "a person with no history gets the empty state, and no about card or filters" do
    sign_in_as(@manager)

    get person_site_log_path(person(:inactive_ranger))

    assert_response :success
    # With no card to open, the empty state says where the history starts.
    assert_match "No on-site or off-site changes are recorded for this person. " \
                 "The history starts in April 2019", response.body
    assert_report_card count: 0
    assert_select "#person-site-log-filters", count: 0
  end

  # --- Filters ------------------------------------------------------------------

  test "marked narrows the history to one kind of change, under filter[...] names" do
    sign_in_as(@manager)

    { PersonOnSite::ON_SITE => /On Site/, PersonOnSite::OFF_SITE => /Off Site/ }.each do |marked, badge|
      get person_site_log_path(@target, filter: { marked: })

      assert_equal 1, table_rows.size, marked
      assert_match badge, table_rows.first
      assert_match "Showing 1 of 2 changes", response.body
    end
    assert_select "select[name=?]", "filter[marked]"
    assert_select "select[name=?]", "filter[sort]"
    assert_unique_dom_ids
  end

  test "oldest first reverses the order, and a same-second pair keeps the order it was made in" do
    on_site_row(PersonOnSite::ON_SITE, @manager.id, @left.created_at)
    sign_in_as(@manager)

    get person_site_log_path(@target, filter: { sort: "asc" })

    rows = table_rows
    assert_match(/Aug 23.*On Site/, rows[0])
    assert_match(/Sep 4.*Off Site/, rows[1])
    assert_match(/Sep 4.*On Site/, rows[2])
  end

  # January, when a Pacific clock runs an hour behind Phoenix: bounds built in
  # Time.zone would take in the half hour before From and drop the last half
  # hour of Through. The edge rows alternate on and off, so the two kept, newest
  # first, read on then off only when the right ones are kept.
  test "a date range takes whole days on the local clock, the through day included" do
    on_site_row(PersonOnSite::ON_SITE, nil, Time.local(2026, 1, 14, 23, 30))
    on_site_row(PersonOnSite::OFF_SITE, nil, Time.local(2026, 1, 15, 0, 0))
    on_site_row(PersonOnSite::ON_SITE, nil, Time.local(2026, 1, 16, 23, 30))
    on_site_row(PersonOnSite::OFF_SITE, nil, Time.local(2026, 1, 17, 0, 0))
    sign_in_as(@manager)

    get person_site_log_path(@target, filter: { starts_on: "2026-01-15", ends_on: "2026-01-16" })

    rows = table_rows
    assert_equal 2, rows.size
    assert_match(/On Site/, rows.first)
    assert_match(/Off Site/, rows.second)
    assert_match "Showing 2 of 6 changes", response.body
    %w[starts_on ends_on].each do |name|
      assert_select "input[type=date][name=?][min=?][max=?]", "filter[#{name}]", "1998-01-01", "2100-12-31"
    end
  end

  test "marked by narrows the history to one creator, or to changes no one was signed in to make" do
    sign_in_as(@manager)

    get person_site_log_path(@target, filter: { creator: @manager.id })

    assert_equal 1, table_rows.size
    assert_match(/On Site.*#{@manager.callsign}/, table_rows.first)

    get person_site_log_path(@target, filter: { creator: PersonOnSiteFilterForm::NO_CREATOR })

    assert_equal 1, table_rows.size
    assert_match(/Off Site.*System/, table_rows.first)
    assert_select "a[aria-label=?]", "Remove filter: Marked By: System"
  end

  test "the marked by options count each creator, commonest first, ties by name" do
    sign_in_as(@manager)

    # One change each: System ties with a callsign, and the tie reads by name.
    get person_site_log_path(@target)

    assert_equal ["All", "#{@manager.callsign} (1)", "System (1)"], creator_options

    2.times { on_site_row(PersonOnSite::OFF_SITE, nil, Time.zone.local(2025, 9, 10 + it, 9, 0)) }
    get person_site_log_path(@target)

    assert_equal ["All", "System (3)", "#{@manager.callsign} (1)"], creator_options
  end

  test "a tie reads by name whatever its case" do
    lower = person(:retired_ranger)
    lower.update_columns(callsign: "abc")
    on_site_row(PersonOnSite::OFF_SITE, lower.id, Time.zone.local(2025, 9, 10, 9, 0))
    sign_in_as(@manager)

    get person_site_log_path(@target)

    assert_equal ["All", "abc (1)", "#{@manager.callsign} (1)", "System (1)"], creator_options
  end

  test "each marked by count is what choosing it shows under the other filters, in unchanged order" do
    2.times { on_site_row(PersonOnSite::OFF_SITE, nil, Time.zone.local(2025, 9, 10 + it, 9, 0)) }
    sign_in_as(@manager)

    # System still leads on its 3 changes overall, but none of them is on site.
    get person_site_log_path(@target, filter: { marked: PersonOnSite::ON_SITE })
    assert_equal ["All", "System (0)", "#{@manager.callsign} (1)"], creator_options

    get person_site_log_path(@target, filter: { ends_on: "2025-09-05" })
    assert_equal ["All", "System (1)", "#{@manager.callsign} (1)"], creator_options

    # The creator filter itself does not narrow the choices it offers.
    get person_site_log_path(@target, filter: { creator: @manager.id })
    assert_equal ["All", "System (3)", "#{@manager.callsign} (1)"], creator_options
  end

  test "a value the page does not know filters nothing and draws no chip" do
    sign_in_as(@manager)

    [{ marked: "all", sort: "desc" }, { marked: "maybe", sort: "sideways" }, "x",
     { starts_on: "99999-01-01" }, { ends_on: "9999-12-31" }, { starts_on: "garbage", ends_on: "2026-13-45" },
     { creator: person(:retired_ranger).id },
     # Rails' multiparameter keys, which permit lets through.
     { "starts_on(1i)" => "2026", "marked(2i)" => "on-site" }].each do |filter|
      get person_site_log_path(@target, filter:)

      assert_response :success
      assert_equal 2, table_rows.size, filter.inspect
      assert_select "a[aria-label^=?]", "Remove filter", count: 0
    end
  end

  test "each chip drops only its own filter, and clear all returns to the whole history" do
    sign_in_as(@manager)

    get person_site_log_path(@target, filter: { marked: PersonOnSite::OFF_SITE, sort: "asc" })

    assert_select "a[aria-label=?][href=?]", "Remove filter: Marked: Off Site",
                  person_site_log_path(@target, filter: { sort: "asc" })
    assert_select "a[aria-label=?][href=?]", "Remove filter: Order: Oldest first",
                  person_site_log_path(@target, filter: { marked: PersonOnSite::OFF_SITE })
    assert_select "a[href=?]", person_site_log_path(@target), text: /Clear All Filters/

    get person_site_log_path(@target, filter: { sort: "asc" })

    assert_select "a[aria-label=?][href=?]", "Remove filter: Order: Oldest first", person_site_log_path(@target)

    get person_site_log_path(@target, filter: { starts_on: "2025-08-01", ends_on: "2025-09-30" })

    assert_select "a[aria-label=?][href=?]", "Remove filter: From: 2025-08-01",
                  person_site_log_path(@target, filter: { ends_on: "2025-09-30" })
    assert_select "a[aria-label=?][href=?]", "Remove filter: Through: 2025-09-30",
                  person_site_log_path(@target, filter: { starts_on: "2025-08-01" })

    get person_site_log_path(@target, filter: { marked: PersonOnSite::ON_SITE, creator: @manager.id })

    assert_select "a[aria-label=?][href=?]", "Remove filter: Marked By: #{@manager.callsign}",
                  person_site_log_path(@target, filter: { marked: PersonOnSite::ON_SITE })
  end

  test "filters that match nothing say so, and keep the bar to clear them" do
    @left.destroy!
    sign_in_as(@manager)

    get person_site_log_path(@target, filter: { marked: PersonOnSite::OFF_SITE })

    # A filter set before the history starts finds nothing for that reason alone.
    assert_match "No changes match the current filters. The history starts in April 2019", response.body
    assert_select "#person-site-log-filters"
    assert_select "a[href=?]", person_site_log_path(@target), text: /Clear All Filters/
  end

  private

  def on_site_row(action, creator_person_id, created_at)
    PersonOnSite.create!(person: @target, creator_person_id:, action:, created_at:)
  end

  def table_rows = css_select("tbody tr").map { |row| row.text.squish }

  def year_headings = css_select("[role=heading][aria-level='2']").map { it.text.squish }

  def creator_options = css_select("select[name='filter[creator]'] option").map { it.text.strip }
end
