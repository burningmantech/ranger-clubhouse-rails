# frozen_string_literal: true

require "test_helper"

class AssetManagement::RadioCheckoutControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include ActiveSupport::Testing::TimeHelpers
  include DomIdTestHelper

  SUMMARY = AssetManagement::RadioCheckoutController::SUMMARY_VIEW
  HOUR = 3600

  setup do
    travel_to Time.zone.local(2026, 8, 30, 12, 0, 0)
    Rails.cache.clear
    Current.reset

    ActionLog.delete_all
    PersonAsset.delete_all
    Asset.delete_all
    # The fixtures hand active_ranger an available event-radio provision, which
    # would silently move them to the eligible cohort in every test here.
    Provision.delete_all

    @admin = person(:auditor_ranger)
    @editor = person(:active_ranger)
    @event_manager = person(:echelon_ranger)
    @unauthorized = person(:ranger_with_custom_gender)
    @holder = person(:inactive_ranger)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::EDIT_ASSETS, "Edit Assets")
    ensure_role(Role::EVENT_MANAGEMENT, "Event Management")
    ensure_role(Role::TRAINER, "Trainer")

    grant_role(@admin, Role::ADMIN)
    grant_role(@editor, Role::EDIT_ASSETS)
    grant_role(@event_manager, Role::EVENT_MANAGEMENT)
    grant_role(@unauthorized, Role::TRAINER)
  end

  teardown do
    Current.reset
    travel_back
    Rails.cache.clear
  end

  test "unauthorized user is redirected" do
    sign_in_as(@unauthorized)

    get asset_management_radio_checkout_path

    assert_redirected_to me_root_path
  end

  test "readers with any asset-viewing role can open the report" do
    check_out(create_radio(barcode: "4831"), @holder, hours_ago: 20)

    [@admin, @editor, @event_manager].each do |reader|
      sign_in_as(reader)

      get asset_management_radio_checkout_path
      assert_response :success
      # The page's own heading, not the body: the sidebar carries a "Radio
      # Checkout Report" menu item on every page in this namespace, so a body
      # match proves nothing about what the controller rendered.
      assert_select "h1", text: /Radio Checkout Report/
      assert_select "td[data-label=Barcode]", text: "4831"
    end
  end

  test "only checkouts past the hour limit are listed" do
    check_out(create_radio(barcode: "SHORT"), @holder, hours_ago: 13)
    check_out(create_radio(barcode: "LONG"), @holder, hours_ago: 15)

    sign_in_as(@admin)
    get asset_management_radio_checkout_path

    assert_response :success
    assert_select "td[data-label=Barcode]", text: "LONG"
    assert_select "td[data-label=Barcode]", text: "SHORT", count: 0
  end

  test "only handheld radios are listed" do
    check_out(create_radio(barcode: "4831"), @holder, hours_ago: 20)
    check_out(create_radio(barcode: "GEAR-1", type: Asset::TYPE_GEAR), @holder, hours_ago: 20)
    check_out(create_radio(barcode: "DESK-1", type: Asset::TYPE_DESKTOP_RADIO), @holder,
              hours_ago: 20)

    sign_in_as(@admin)
    get asset_management_radio_checkout_path

    assert_response :success
    assert_select "td[data-label=Barcode]", text: "4831"
    assert_select "td[data-label=Barcode]", text: "GEAR-1", count: 0
    assert_select "td[data-label=Barcode]", text: "DESK-1", count: 0
  end

  test "a holder with no event radio provision is overdue and one with a provision is not" do
    check_out(create_radio(barcode: "OVERDUE"), @holder, hours_ago: 20)
    check_out(create_radio(barcode: "ALLOWED"), @editor, hours_ago: 40)
    grant_event_radio(@editor)

    sign_in_as(@admin)
    get asset_management_radio_checkout_path

    assert_response :success
    assert_select "[role=heading]", text: /Overdue — No Event Radio Provision/
    assert_select "[role=heading]", text: /Event Radio Eligible Holders/
    # The split is the whole report, so which table each row lands in is the
    # claim worth pinning -- a page-wide match would pass on one merged table.
    tables = css_select("table")
    assert_equal 2, tables.size
    assert_select tables[0], "td[data-label=Barcode]", text: "OVERDUE"
    assert_select tables[0], "td[data-label=Barcode]", text: "ALLOWED", count: 0
    assert_select tables[1], "td[data-label=Barcode]", text: "ALLOWED"
  end

  test "the eligible section is omitted when no one holds a provision" do
    check_out(create_radio(barcode: "OVERDUE"), @holder, hours_ago: 20)

    sign_in_as(@admin)
    get asset_management_radio_checkout_path

    assert_response :success
    assert_select "[role=heading]", text: /Overdue — No Event Radio Provision/
    assert_select "[role=heading]", text: /Event Radio Eligible Holders/, count: 0
  end

  test "the overdue section states the good news rather than disappearing" do
    check_out(create_radio(barcode: "ALLOWED"), @editor, hours_ago: 40)
    grant_event_radio(@editor)

    sign_in_as(@admin)
    get asset_management_radio_checkout_path

    assert_response :success
    assert_select "[role=heading]", text: /Overdue — No Event Radio Provision/
    assert_select "body", text: /Every radio listed is held by someone entitled to keep it/
  end

  test "an available provision counts for the current year only" do
    check_out(create_radio(barcode: "PAST", year: Current.year - 1), @editor,
              hours_ago: 20, at: Time.zone.local(Current.year - 1, 8, 30, 12, 0, 0))
    # Available, never consumed: today it makes the holder eligible, but it says
    # nothing about a radio they kept last year.
    grant_event_radio(@editor, status: Provision::AVAILABLE, source_year: Current.year - 1)

    sign_in_as(@admin)
    get asset_management_radio_checkout_path(year: Current.year - 1)

    assert_response :success
    assert_select "td[data-label=Barcode]", text: "PAST"
    assert_select "[role=heading]", text: /Event Radio Eligible Holders/, count: 0
  end

  test "a provision consumed in the reported year counts in a past year" do
    check_out(create_radio(barcode: "PAST", year: Current.year - 1), @editor,
              hours_ago: 20, at: Time.zone.local(Current.year - 1, 8, 30, 12, 0, 0))
    grant_event_radio(@editor, status: Provision::USED, source_year: Current.year - 1,
                               consumed_year: Current.year - 1)

    sign_in_as(@admin)
    get asset_management_radio_checkout_path(year: Current.year - 1)

    assert_response :success
    assert_select "[role=heading]", text: /Event Radio Eligible Holders/
    assert_select "[role=heading]", text: /Overdue — No Event Radio Provision/
    assert_select "body", text: /Every radio listed is held by someone entitled to keep it/
  end

  test "the report is scoped to the selected year" do
    check_out(create_radio(barcode: "NOW"), @holder, hours_ago: 20)
    check_out(create_radio(barcode: "THEN", year: Current.year - 1), @holder,
              hours_ago: 20, at: Time.zone.local(Current.year - 1, 8, 30, 12, 0, 0))

    sign_in_as(@admin)

    get asset_management_radio_checkout_path(year: Current.year - 1)
    assert_response :success
    assert_select "td[data-label=Barcode]", text: "THEN"
    assert_select "td[data-label=Barcode]", text: "NOW", count: 0

    # An unusable year falls back to the most recent year with checkouts.
    get asset_management_radio_checkout_path(year: "not-a-year")
    assert_response :success
    assert_select "td[data-label=Barcode]", text: "NOW"
  end

  test "the default year skips a newer year whose radios all came back" do
    # Last year's stray is the recovery list the quartermaster is here for; the
    # first scan of this year's radios must not bury it.
    check_out(create_radio(barcode: "STRAY", year: Current.year - 1), @holder,
              hours_ago: 60, at: Time.zone.local(Current.year - 1, 8, 30, 12, 0, 0))
    check_out(create_radio(barcode: "SCANNED"), @holder, hours_ago: 3, returned_hours_ago: 2)

    sign_in_as(@admin)
    get asset_management_radio_checkout_path

    assert_response :success
    assert_select "td[data-label=Barcode]", text: "STRAY"
    assert_select "select[name=year] option[selected][value=?]", (Current.year - 1).to_s
  end

  test "arriving on a year with no radio checkouts says which year is shown instead" do
    check_out(create_radio(barcode: "STRAY"), @holder, hours_ago: 20)
    # A year the sibling asset pages offer but this one cannot: radios exist,
    # none ever left the cage. The sidebar carries the reader's year here.
    create_radio(barcode: "NEVER-OUT", year: Current.year - 1)

    sign_in_as(@admin)
    get asset_management_radio_checkout_path(year: Current.year - 1)

    assert_response :success
    assert_select "body", text: /No radios were checked out in #{Current.year - 1}/
    assert_select "body", text: /Showing #{Current.year} instead/
    assert_select "td[data-label=Barcode]", text: "STRAY"
  end

  test "a year that is simply unknown falls back without a callout" do
    check_out(create_radio(barcode: "STRAY"), @holder, hours_ago: 20)

    sign_in_as(@admin)
    get asset_management_radio_checkout_path(year: 1998)

    assert_response :success
    assert_select "body", text: /No radios were checked out in/, count: 0
  end

  test "the eligible audit list is capped and says so, while the chase list is never cut" do
    limit = AssetManagement::RadioCheckoutController::ELIGIBLE_DISPLAY_LIMIT
    grant_event_radio(@editor)
    (limit + 2).times { |n| check_out(create_radio(barcode: "E#{n}"), @editor, hours_ago: 20) }
    check_out(create_radio(barcode: "OVERDUE"), @holder, hours_ago: 20)

    sign_in_as(@admin)
    get asset_management_radio_checkout_path

    assert_response :success
    tables = css_select("table")
    assert_select tables[0], "tbody tr", count: 1
    assert_select tables[1], "tbody tr", count: limit
    assert_select "body", text: /Showing the #{limit} longest-held of #{limit + 2} radios/

    # The export is never cut -- it is what the note points the reader at.
    get asset_management_radio_checkout_path(format: :csv)
    assert_response :success
    assert_equal limit + 4, response.body.lines.size
  end

  test "returned radios appear only in the event summary" do
    check_out(create_radio(barcode: "BACK-LATE"), @holder, hours_ago: 30, returned_hours_ago: 2)
    check_out(create_radio(barcode: "STILL-OUT"), @holder, hours_ago: 20)

    sign_in_as(@admin)

    get asset_management_radio_checkout_path
    assert_response :success
    assert_select "td[data-label=Barcode]", text: "STILL-OUT"
    assert_select "td[data-label=Barcode]", text: "BACK-LATE", count: 0
    # Nothing on screen has come back, so the column would read "Still out" on
    # every row.
    assert_select "th", text: "Checked In / By", count: 0

    get asset_management_radio_checkout_path(view: SUMMARY)
    assert_response :success
    assert_select "td[data-label=Barcode]", text: "BACK-LATE"
    assert_select "td[data-label=Barcode]", text: "STILL-OUT"
    assert_select "th", text: "Checked In / By"
  end

  test "a radio returned inside the limit stays out of the event summary" do
    check_out(create_radio(barcode: "PROMPT"), @holder, hours_ago: 4, returned_hours_ago: 1)
    # Still out but only briefly: unaccounted for, so the after-action audit
    # wants it however short the span.
    check_out(create_radio(barcode: "BRIEF"), @holder, hours_ago: 2)

    sign_in_as(@admin)
    get asset_management_radio_checkout_path(view: SUMMARY)

    assert_response :success
    assert_select "td[data-label=Barcode]", text: "BRIEF"
    assert_select "td[data-label=Barcode]", text: "PROMPT", count: 0
  end

  test "the event summary never calls a short checkout overdue" do
    # Out for two hours and nowhere near the limit, but unaccounted for, so the
    # after-action view carries it. Every count and heading around it has to
    # stop saying "overdue" and "out too long" or the page libels this row.
    check_out(create_radio(barcode: "BRIEF"), @holder, hours_ago: 2)
    check_out(create_radio(barcode: "LONG"), @holder, hours_ago: 20)

    sign_in_as(@admin)
    get asset_management_radio_checkout_path(view: SUMMARY)

    assert_response :success
    assert_select "td[data-label=Barcode]", text: "BRIEF"
    assert_select "body", text: /out for more than 14 hours/, count: 0
    assert_select "body", text: /Overdue radios/, count: 0
    assert_select "body", text: /Radios out too long/, count: 0
    assert_select "[role=heading]", text: /Overdue/, count: 0
    assert_select "[role=heading]", text: /No Event Radio Provision/

    # The chase list is defined by the limit, so there the same words are exact
    # -- and BRIEF is not on it to contradict them.
    get asset_management_radio_checkout_path
    assert_response :success
    assert_select "td[data-label=Barcode]", text: "BRIEF", count: 0
    assert_select "body", text: /out for more than 14 hours/
    assert_select "body", text: /Overdue radios/
    assert_select "[role=heading]", text: /Overdue — No Event Radio Provision/
  end

  test "a forced check-out is flagged" do
    check_out(create_radio(barcode: "4823"), @holder, hours_ago: 20, forced: true)

    sign_in_as(@admin)
    get asset_management_radio_checkout_path

    assert_response :success
    assert_select "body", text: /Check-out forced/
  end

  test "duration is stated in hours and minutes, and in days once past one" do
    check_out(create_radio(barcode: "HOURS"), @holder, hours_ago: 18.5)
    check_out(create_radio(barcode: "DAYS"), @holder, hours_ago: 50)

    sign_in_as(@admin)
    get asset_management_radio_checkout_path

    assert_response :success
    assert_select "td[data-label=Duration]", text: "18:30"
    assert_select "td[data-label=Duration]", text: "2 days 2 hours"
  end

  test "both views are always offered, with the one on screen marked current" do
    check_out(create_radio(barcode: "4831"), @holder, hours_ago: 20)

    chase = asset_management_radio_checkout_path(year: Current.year)
    summary = asset_management_radio_checkout_path(year: Current.year, view: SUMMARY)

    sign_in_as(@admin)

    get chase
    assert_response :success
    # Neither button ever disappears, so the reader can always see which two
    # views exist and which one they are on.
    assert_select "a[href=?]", chase, text: /Still Out Now/
    assert_select "a[href=?]", summary, text: /Event Summary/
    # Not the fill alone. Asserted on the accessible name rather than
    # aria-current, which active_links_controller rewrites on every link on the
    # page -- a server-side assertion on that attribute would pass here and
    # still be wrong in a browser.
    assert_select "a[href=?] .sr-only", chase, text: /current view/
    assert_select "a[href=?] .sr-only", summary, count: 0

    get summary
    assert_response :success
    assert_select "a[href=?]", chase, text: /Still Out Now/
    assert_select "a[href=?]", summary, text: /Event Summary/
    assert_select "a[href=?] .sr-only", summary, text: /current view/
    assert_select "a[href=?] .sr-only", chase, count: 0
  end

  test "the view rides on the year selector and the export link" do
    check_out(create_radio(barcode: "4831"), @holder, hours_ago: 20)

    sign_in_as(@admin)
    get asset_management_radio_checkout_path(view: SUMMARY)

    assert_response :success
    # hero_panel renders the year selector twice (desktop and mobile) and its
    # id: lands on the heading rather than on a wrapper, so the count is what
    # pins this: both copies must carry the view or one of them silently
    # returns the reader to the chase list.
    assert_select "input[type=hidden][name=view][value=?]", SUMMARY, count: 2
    assert_select "a[href=?]",
                  asset_management_radio_checkout_path(year: Current.year, view: SUMMARY,
                                                       format: :csv)
  end

  test "the export covers both cohorts with the verdict as a column" do
    check_out(create_radio(barcode: "OVERDUE"), @holder, hours_ago: 20)
    check_out(create_radio(barcode: "ALLOWED"), @editor, hours_ago: 40)
    grant_event_radio(@editor)

    sign_in_as(@admin)
    get asset_management_radio_checkout_path(format: :csv)

    assert_response :success
    assert_equal "text/csv", response.media_type
    assert_match(/filename="#{Current.year}-radio-checkout\.csv"/,
                 response.headers["Content-Disposition"])

    lines = response.body.lines.map(&:chomp)
    assert_equal "Callsign,Barcode,Duration (Hours),Checked Out,Checked Out By,Checked In," \
                 "Checked In By,Check-out Forced?,Event Radio?,Event Radio Eligible?",
                 lines.first
    # Longest held first, so the eligible 40-hour row leads.
    assert_match(/,ALLOWED,40\.00,/, lines[1])
    assert_match(/,No,No,Yes\z/, lines[1])
    assert_match(/,OVERDUE,20\.00,/, lines[2])
    assert_match(/,No,No,No\z/, lines[2])
  end

  test "the summary export gets its own filename and fills the check-in columns" do
    returned = check_out(create_radio(barcode: "BACK-LATE"), @holder,
                         hours_ago: 30, returned_hours_ago: 2)

    sign_in_as(@admin)
    get asset_management_radio_checkout_path(view: SUMMARY, format: :csv)

    assert_response :success
    assert_match(/filename="#{Current.year}-summary-radio-checkout\.csv"/,
                 response.headers["Content-Disposition"])

    # Every column by position, so a value moving between columns cannot pass:
    # the chase-view export can only ever leave the two check-in ones blank.
    row = response.body.lines.map(&:chomp).last.split(",")
    assert_equal [@holder.callsign, "BACK-LATE", "28.00",
                  returned.checked_out.iso8601, @admin.callsign,
                  returned.checked_in.iso8601, @event_manager.callsign,
                  "No", "No", "No"],
                 row
  end

  test "a still-out radio exports blank check-in columns rather than shifting them" do
    check_out(create_radio(barcode: "STILL-OUT"), @holder, hours_ago: 20)

    sign_in_as(@admin)
    get asset_management_radio_checkout_path(format: :csv)

    assert_response :success
    row = response.body.lines.map(&:chomp).last.split(",", -1)
    assert_equal 10, row.size
    assert_equal ["", ""], row[5, 2]
  end

  test "the summary table names who took each radio back" do
    check_out(create_radio(barcode: "BACK-LATE"), @holder, hours_ago: 30, returned_hours_ago: 2)

    sign_in_as(@admin)
    get asset_management_radio_checkout_path(view: SUMMARY)

    assert_response :success
    assert_select "td[data-label=?]", "Checked In / By", text: /by #{@event_manager.callsign}/
  end

  test "a quiet year says so rather than showing empty sections" do
    check_out(create_radio(barcode: "SHORT"), @holder, hours_ago: 2)

    sign_in_as(@admin)
    get asset_management_radio_checkout_path

    assert_response :success
    assert_select "body", text: /No radios have been out longer than 14 hours/
    assert_select "[role=heading]", text: /Overdue — No Event Radio Provision/, count: 0
  end

  test "a year that never checked a radio out shows the no-records state" do
    sign_in_as(@admin)
    get asset_management_radio_checkout_path

    assert_response :success
    assert_select "body", text: /No radios have ever been checked out/
  end

  test "a malformed year param falls back instead of raising" do
    check_out(create_radio(barcode: "4831"), @holder, hours_ago: 20)

    sign_in_as(@admin)

    get "/asset-management/radio-checkout?year[]=#{Current.year}"
    assert_response :success
    assert_select "td[data-label=Barcode]", text: "4831"

    get "/asset-management/radio-checkout?year[bogus]=1"
    assert_response :success
  end

  test "the page has no duplicate dom ids" do
    check_out(create_radio(barcode: "OVERDUE"), @holder, hours_ago: 20)
    check_out(create_radio(barcode: "ALLOWED"), @editor, hours_ago: 40)
    grant_event_radio(@editor)

    sign_in_as(@admin)
    get asset_management_radio_checkout_path

    assert_response :success
    assert_unique_dom_ids
  end

  private

  def ensure_role(id, title)
    role = Role.find_or_initialize_by(id: id)
    role.title = title
    role.new_user_eligible = false
    role.save!
  end

  def grant_role(person, role_id)
    PersonRole.find_or_create_by!(person_id: person.id, role_id: role_id)
    RoleManager.purge_person(person.id.to_s)
  end

  def create_radio(**attributes)
    Asset.create!(
      {
        barcode: "RADIO-#{next_sequence}",
        type: Asset::TYPE_RADIO,
        description: "Ranger Event 26-065",
        perm_assign: false,
        year: Current.year
      }.merge(attributes)
    )
  end

  # at: anchors a past year's checkout to that year's event; hours_ago and
  # returned_hours_ago are measured from it. A returned radio always records who
  # took it back, so the check-in person columns have something to render.
  def check_out(asset, holder, hours_ago:, returned_hours_ago: nil, forced: false,
                at: Current.time)
    PersonAsset.create!(asset:,
                        person_id: holder.id,
                        checked_out: at - (hours_ago * HOUR),
                        checked_in: (at - (returned_hours_ago * HOUR) if returned_hours_ago),
                        check_out_person_id: @admin.id,
                        check_in_person_id: (@event_manager.id if returned_hours_ago),
                        check_out_forced: forced)
  end

  def grant_event_radio(holder, status: Provision::AVAILABLE, source_year: Current.year,
                        consumed_year: nil)
    Provision.create!(person_id: holder.id,
                      type: Provision::EVENT_RADIO,
                      status:,
                      consumed_year:,
                      is_allocated: false,
                      item_count: 1,
                      source_year:,
                      expires_on: "#{source_year}-09-15")
  end

  def next_sequence
    @next_sequence = (@next_sequence || 0) + 1
  end
end
