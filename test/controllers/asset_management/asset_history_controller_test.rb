# frozen_string_literal: true

require "test_helper"

class AssetManagement::AssetHistoryControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include ActiveSupport::Testing::TimeHelpers
  include DomIdTestHelper

  setup do
    travel_to Time.zone.local(2026, 4, 16, 12, 0, 0)
    Rails.cache.clear
    Current.reset

    ActionLog.delete_all
    PersonAsset.delete_all
    Asset.delete_all

    @admin = person(:auditor_ranger)
    @editor = person(:active_ranger)
    @event_manager = person(:echelon_ranger)
    @unauthorized = person(:ranger_with_custom_gender)

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

    get asset_management_asset_history_path

    assert_redirected_to me_root_path
  end

  test "readers with any asset-viewing role can open the report" do
    check_out(gear(barcode: "GEAR-100"), @editor)

    [@admin, @editor, @event_manager].each do |reader|
      sign_in_as(reader)

      get asset_management_asset_history_path
      assert_response :success
      assert_select "body", text: /Asset History/
      assert_select "th", text: /GEAR-100/
    end
  end

  test "the ledger lists one row per checkout, not per asset" do
    twice = gear(barcode: "GEAR-TWICE")
    check_in(check_out(twice, @editor))
    check_out(twice, @event_manager)
    gear(barcode: "GEAR-SHELF")

    sign_in_as(@admin)
    get asset_management_asset_history_path

    assert_response :success
    assert_select "th", text: /GEAR-TWICE/, count: 2
    # An asset that never went out has no history and so contributes no row.
    assert_select "th", text: /GEAR-SHELF/, count: 0
    assert_select "span", text: "Showing 2 checkouts"
    # Two checkouts, but one asset and two holders.
    assert_select "div", text: /\A2\s*Checkouts Recorded\z/
    assert_select "div", text: /\A1\s*Assets Checked Out\z/
    assert_select "div", text: /\A2\s*People Who Took Assets\z/
  end

  test "handheld radios are excluded by default but other radio types are not" do
    check_out(gear(barcode: "GEAR-1"), @editor)
    check_out(create_asset(barcode: "HANDHELD-1", type: Asset::TYPE_RADIO), @editor)
    check_out(create_asset(barcode: "CHARGER-1", type: Asset::TYPE_RADIO_CHARGER), @editor)
    check_out(create_asset(barcode: "DESKTOP-1", type: Asset::TYPE_DESKTOP_RADIO), @editor)

    sign_in_as(@admin)
    get asset_management_asset_history_path

    assert_response :success
    assert_select "th", text: /GEAR-1/
    assert_select "th", text: /CHARGER-1/
    assert_select "th", text: /DESKTOP-1/
    assert_select "th", text: /HANDHELD-1/, count: 0
    assert_select "span", text: "Showing 3 checkouts"
  end

  test "selecting Radio opts handhelds back in and drops everything else" do
    check_out(gear(barcode: "GEAR-1"), @editor)
    check_out(create_asset(barcode: "HANDHELD-1", type: Asset::TYPE_RADIO), @editor)

    sign_in_as(@admin)
    get asset_management_asset_history_path(type: Asset::TYPE_RADIO)

    assert_response :success
    assert_select "th", text: /HANDHELD-1/
    assert_select "th", text: /GEAR-1/, count: 0
    assert_select "span", text: "Showing 1 checkout"
    # Stats describe the filtered ledger, or the headline would contradict the
    # rows under it.
    assert_select "div", text: /\A1\s*Checkouts Recorded\z/
  end

  test "the type select offers radios even though the default scope omits them" do
    check_out(gear(barcode: "GEAR-1"), @editor)
    check_out(create_asset(barcode: "HANDHELD-1", type: Asset::TYPE_RADIO), @editor)

    sign_in_as(@admin)
    get asset_management_asset_history_path

    assert_response :success
    assert_select "select[name=type] option[value=?]", Asset::TYPE_RADIO
    # The "all" label has to state the exclusion or it promises rows it hides.
    assert_select "select[name=type] option", text: "All except radios"
  end

  test "an unrecognized type filter falls back to the default scope" do
    check_out(gear(barcode: "GEAR-1"), @editor)

    sign_in_as(@admin)
    get asset_management_asset_history_path(type: "bogus")

    assert_response :success
    assert_select "th", text: /GEAR-1/
    assert_select "span", text: "Showing 1 checkout"
  end

  test "a type with no assets in the selected year falls back rather than emptying" do
    check_out(gear(barcode: "GEAR-1"), @editor)

    sign_in_as(@admin)
    get asset_management_asset_history_path(type: Asset::TYPE_TEMP_ID)

    assert_response :success
    assert_select "th", text: /GEAR-1/
    assert_select "span", text: "Showing 1 checkout"
  end

  test "the outcome filter splits returned from never-returned" do
    check_in(check_out(gear(barcode: "GEAR-BACK"), @editor))
    check_out(gear(barcode: "GEAR-GONE"), @editor)

    sign_in_as(@admin)

    get asset_management_asset_history_path(outcome: "outstanding")
    assert_response :success
    assert_select "th", text: /GEAR-GONE/
    assert_select "th", text: /GEAR-BACK/, count: 0

    get asset_management_asset_history_path(outcome: "returned")
    assert_response :success
    assert_select "th", text: /GEAR-BACK/
    assert_select "th", text: /GEAR-GONE/, count: 0

    get asset_management_asset_history_path(outcome: "bogus")
    assert_response :success
    assert_select "th", text: /GEAR-BACK/
    assert_select "th", text: /GEAR-GONE/
  end

  test "an unreturned checkout is called out instead of showing a duration" do
    check_out(gear(barcode: "GEAR-GONE"), @editor)

    sign_in_as(@admin)
    get asset_management_asset_history_path

    assert_response :success
    assert_select "span", text: "Never returned"
    assert_select "div", text: /\A1\s*Never Returned\z/
    # PersonAsset#duration measures an open checkout to "now", which on a past
    # year's ledger would claim the asset has been out for hundreds of days.
    # Anchored on the column: the Description cell renders the same em dash for
    # this fixture, so a bare `assert_select "td", text: "—"` passes whether or
    # not the Duration cell is right.
    assert_select "td[data-label=Duration]", text: "—"

    get asset_management_asset_history_path(format: :csv)
    assert_response :success
    assert_equal "GEAR-GONE", response.body.lines.last.split(",").first
    assert response.body.lines.last.chomp.end_with?(","),
           "an open checkout must export a blank duration, not a span measured to now"
  end

  test "durations past a day are said in days rather than hundreds of hours" do
    long = check_out(gear(barcode: "GEAR-LONG"), @editor)
    long.update!(checked_out: Current.time - 12.days - 7.hours, checked_in: Current.time,
                 check_in_person_id: @admin.id)
    short = check_out(gear(barcode: "GEAR-SHORT"), @editor)
    short.update!(checked_out: Current.time - 3.hours - 20.minutes, checked_in: Current.time,
                  check_in_person_id: @admin.id)

    sign_in_as(@admin)
    get asset_management_asset_history_path

    assert_response :success
    assert_select "td", text: "12 days 7 hours"
    assert_select "td", text: "3 hours 20 mins"
  end

  test "the report is scoped to the selected year" do
    check_out(gear(barcode: "GEAR-NOW"), @editor)
    check_out(gear(barcode: "GEAR-THEN", year: Current.year - 1), @editor)

    sign_in_as(@admin)

    get asset_management_asset_history_path(year: Current.year - 1)
    assert_response :success
    assert_select "th", text: /GEAR-THEN/
    assert_select "th", text: /GEAR-NOW/, count: 0

    get asset_management_asset_history_path(year: "not-a-year")
    assert_response :success
    assert_select "th", text: /GEAR-NOW/
  end

  test "the default year is the newest one that recorded a checkout" do
    check_out(gear(barcode: "GEAR-THEN", year: Current.year - 1), @editor)
    # Next season's inventory exists but nothing has gone out in it yet.
    gear(barcode: "GEAR-SHELF")

    sign_in_as(@admin)
    get asset_management_asset_history_path

    assert_response :success
    assert_select "th", text: /GEAR-THEN/
  end

  test "a malformed year param falls back instead of raising" do
    check_out(gear(barcode: "GEAR-1"), @editor)

    sign_in_as(@admin)

    get "/asset-management/asset-history?year[]=#{Current.year}"
    assert_response :success
    assert_select "th", text: /GEAR-1/

    get "/asset-management/asset-history?year[bogus]=1"
    assert_response :success
  end

  test "the year selector and the filter chips each carry the other's state" do
    check_in(check_out(gear(barcode: "GEAR-1"), @editor))

    sign_in_as(@admin)
    get asset_management_asset_history_path(type: Asset::TYPE_GEAR, outcome: "returned")

    assert_response :success
    # The year selector submits its own bare GET, so it has to re-emit the filters.
    assert_select "input[type=hidden][name=type][value=?]", Asset::TYPE_GEAR
    assert_select "input[type=hidden][name=outcome][value=?]", "returned"
    # ...and the filter form has to re-emit the year.
    assert_select "input[type=hidden][name=year][value=?]", Current.year.to_s
    # Removing one chip keeps the year AND the other filter. Scoped by
    # aria-label: the "Clear All Filters" link carries a similar href.
    assert_select "a[aria-label=?][href=?]",
                  "Remove filter: Type: Gear",
                  asset_management_asset_history_path(year: Current.year, outcome: "returned")
    assert_select "a[aria-label=?][href=?]",
                  "Remove filter: Outcome: Returned",
                  asset_management_asset_history_path(year: Current.year, type: Asset::TYPE_GEAR)
  end

  test "the barcode link returns the reader to this report, not the inventory" do
    asset = gear(barcode: "GEAR-1")
    check_out(asset, @editor)

    sign_in_as(@admin)
    get asset_management_asset_history_path(outcome: "outstanding")

    assert_response :success
    assert_select "th a[href*=?]", "origin=history"

    get asset_management_record_path(asset, year: Current.year, outcome: "outstanding",
                                            origin: "history")
    assert_response :success
    assert_select "a[href=?]",
                  asset_management_asset_history_path(year: Current.year, outcome: "outstanding"),
                  text: /Asset history/
  end

  test "the ledger paginates and a filter cannot strand the reader past the last page" do
    120.times { |i| check_out(gear(barcode: format("GEAR-%03d", i)), @editor) }

    sign_in_as(@admin)

    get asset_management_asset_history_path
    assert_response :success
    assert_select "th", text: /GEAR-000/
    assert_select "th", text: /GEAR-119/, count: 0
    assert_select "span", text: "Showing 120 checkouts"

    get asset_management_asset_history_path(page: 2)
    assert_response :success
    assert_select "th", text: /GEAR-119/
    assert_select "th", text: /GEAR-000/, count: 0

    # Out-of-range pages clamp rather than render an empty table.
    get asset_management_asset_history_path(page: 999)
    assert_response :success
    assert_select "th", text: /GEAR-119/

    get asset_management_asset_history_path(page: 0)
    assert_response :success
    assert_select "th", text: /GEAR-000/
  end

  test "a reader who cannot open person pages sees plain callsigns" do
    check_out(gear(barcode: "GEAR-1"), @admin)

    # EDIT_ASSETS reads this page but is not a person-page viewing role.
    sign_in_as(@editor)
    get asset_management_asset_history_path

    assert_response :success
    assert_select "body", text: /#{@admin.callsign}/
    assert_select "a[href^='/person/']", count: 0
  end

  test "a NULL-typed asset does not hijack the unfiltered page" do
    check_out(gear(barcode: "GEAR-1"), @editor)
    untyped = gear(barcode: "MYSTERY")
    # The Laravel-shared table permits a NULL type; write one the way an
    # external writer would, past the Rails presence validation.
    Asset.where(id: untyped.id).update_all(type: nil)
    check_out(untyped, @editor)

    sign_in_as(@admin)
    get asset_management_asset_history_path

    assert_response :success
    assert_select "th", text: /GEAR-1/
    assert_select "th", text: /MYSTERY/
    assert_select "span", text: "Showing 2 checkouts"
  end

  test "a year whose only activity is radios still offers the filter that shows them" do
    check_out(create_asset(barcode: "HANDHELD-1", type: Asset::TYPE_RADIO), @editor)
    gear(barcode: "GEAR-SHELF")

    sign_in_as(@admin)
    get asset_management_asset_history_path

    assert_response :success
    # The default scope hides handhelds, so claiming nothing went out is false...
    assert_select "body", text: /nothing went out that year/, count: 0
    assert_select "body", text: /Only handheld radios went out in #{Current.year}/
    # ...and the control that proves it has to still be on the page.
    assert_select "select[name=type] option[value=?]", Asset::TYPE_RADIO
  end

  test "the default year is one the ledger can actually show, not a radio-only year" do
    check_out(gear(barcode: "GEAR-THEN", year: Current.year - 1), @editor)
    # This year only handhelds have moved -- nothing the default scope renders.
    check_out(create_asset(barcode: "HANDHELD-NOW", type: Asset::TYPE_RADIO), @editor)

    sign_in_as(@admin)
    get asset_management_asset_history_path

    assert_response :success
    assert_select "th", text: /GEAR-THEN/
  end

  test "a year with inventory but no checkouts shows the nothing-happened state" do
    gear(barcode: "GEAR-SHELF")

    sign_in_as(@admin)
    get asset_management_asset_history_path

    assert_response :success
    assert_select "body", text: /nothing went out that year/
  end

  test "an empty inventory shows the no-records state" do
    sign_in_as(@admin)
    get asset_management_asset_history_path

    assert_response :success
    assert_select "body", text: /No asset records have been added yet/
  end

  test "the page has no duplicate DOM ids" do
    check_in(check_out(gear(barcode: "GEAR-1"), @editor))
    check_out(create_asset(barcode: "HANDHELD-1", type: Asset::TYPE_RADIO), @editor)

    sign_in_as(@admin)
    get asset_management_asset_history_path(outcome: "returned")

    assert_response :success
    assert_unique_dom_ids
  end

  test "an attachment reaches the export" do
    # asset_attachment carries no auto-increment -- the id has to be supplied.
    attachment = AssetAttachment.create!(id: 9_101, parent_type: AssetAttachment::RADIO,
                                         description: "Shoulder Mic")
    check_out(gear(barcode: "GEAR-1"), @editor).update!(attachment:)

    sign_in_as(@admin)
    get asset_management_asset_history_path(format: :csv)

    assert_response :success
    assert_includes response.body, "Shoulder Mic"
  end

  test "CSV export carries the full row, honors the filters, and ignores pagination" do
    120.times { |i| check_in(check_out(gear(barcode: format("GEAR-%03d", i)), @editor)) }
    check_out(create_asset(barcode: "HANDHELD-1", type: Asset::TYPE_RADIO), @editor)

    sign_in_as(@admin)
    get asset_management_asset_history_path(format: :csv)

    assert_response :success
    assert_equal "text/csv", response.media_type
    assert_match(/#{Current.year}-asset-history\.csv/, response.headers["Content-Disposition"])

    lines = response.body.lines.map(&:chomp)
    assert_equal "Barcode,Type,Description,Assignment,Callsign,Attachment,Checked Out," \
                 "Checked Out By,Checked In,Checked In By,Duration (seconds)",
                 lines.first
    # 120 gear checkouts plus the header -- the export is not capped at the
    # 100-row page, and the handheld is still out of the default scope.
    assert_equal 121, lines.size
    refute_includes response.body, "HANDHELD-1"
    assert_includes response.body, @editor.callsign
    assert_includes response.body, @admin.callsign

    # A filtered export needs its own filename, or the second download collides.
    get asset_management_asset_history_path(type: Asset::TYPE_RADIO, outcome: "outstanding",
                                            format: :csv)
    assert_response :success
    assert_equal 2, response.body.lines.size
    assert_includes response.body, "HANDHELD-1"
    assert_match(/#{Current.year}-radio-outstanding-asset-history\.csv/,
                 response.headers["Content-Disposition"])
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

  def create_asset(**attributes)
    Asset.create!(
      {
        barcode: "ASSET-#{next_sequence}",
        type: Asset::TYPE_GEAR,
        year: Current.year
      }.merge(attributes)
    )
  end

  def gear(**attributes)
    create_asset(type: Asset::TYPE_GEAR, **attributes)
  end

  def check_out(asset, holder)
    PersonAsset.create!(asset:, person_id: holder.id, checked_out: Current.time,
                        check_out_person_id: @admin.id)
  end

  def check_in(person_asset)
    person_asset.update!(checked_in: Current.time, check_in_person_id: @admin.id)
    person_asset
  end

  def next_sequence
    @next_sequence = (@next_sequence || 0) + 1
  end
end
