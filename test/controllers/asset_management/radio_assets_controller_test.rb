# frozen_string_literal: true

require "test_helper"

class AssetManagement::RadioAssetsControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include ActiveSupport::Testing::TimeHelpers
  include DomIdTestHelper

  SUMMARY = AssetManagement::RadioAssetsController::SUMMARY_VIEW

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

    get asset_management_radio_assets_path

    assert_redirected_to me_root_path
  end

  test "readers with any asset-viewing role can open the report" do
    create_radio(barcode: "101")

    [@admin, @editor, @event_manager].each do |reader|
      sign_in_as(reader)

      get asset_management_radio_assets_path
      assert_response :success
      # The page's own heading, not the body: the sidebar carries a "Radio
      # Assets" menu item on every page in this namespace, so a body match
      # proves nothing about what the controller rendered.
      assert_select "h1", text: /Radio Assets/
      assert_select "th", text: /101/
    end
  end

  test "only handheld radios are listed" do
    create_radio(barcode: "101")
    create_radio(barcode: "GEAR-1", type: Asset::TYPE_GEAR)
    create_radio(barcode: "DESK-1", type: Asset::TYPE_DESKTOP_RADIO)

    sign_in_as(@admin)
    get asset_management_radio_assets_path

    assert_response :success
    assert_select "th", text: /101/
    assert_select "th", text: /GEAR-1/, count: 0
    assert_select "th", text: /DESK-1/, count: 0
  end

  test "each radio is badged event or shift rather than permanent or temporary" do
    create_radio(barcode: "101", perm_assign: true)
    create_radio(barcode: "500", perm_assign: false)

    sign_in_as(@admin)
    get asset_management_radio_assets_path

    assert_response :success
    # Anchored on the column: "Event" also appears in descriptions and in the
    # stat box label, so a bare body match would pass without any badge at all.
    assert_select "td[data-label=Duration]", text: /Event/
    assert_select "td[data-label=Duration]", text: /Shift/
  end

  test "the report is scoped to the selected year" do
    create_radio(barcode: "101")
    create_radio(barcode: "202", year: Current.year - 1)

    sign_in_as(@admin)

    get asset_management_radio_assets_path(year: Current.year - 1)
    assert_response :success
    assert_select "th", text: /202/
    assert_select "th", text: /101/, count: 0

    # An unusable year falls back to the most recent year holding radios.
    get asset_management_radio_assets_path(year: "not-a-year")
    assert_response :success
    assert_select "th", text: /101/
  end

  test "a year holding only non-radio assets is not offered" do
    create_radio(barcode: "101")
    create_radio(barcode: "GEAR-1", type: Asset::TYPE_GEAR, year: Current.year - 1)

    sign_in_as(@admin)
    get asset_management_radio_assets_path(year: Current.year - 1)

    assert_response :success
    # Falls back to the only year with radios rather than opening on an empty one.
    assert_select "th", text: /101/
  end

  test "the summarized view collapses consecutive barcodes and counts them" do
    %w[101 102 103 201 202].each { |barcode| create_radio(barcode:) }

    sign_in_as(@admin)
    get asset_management_radio_assets_path(view: SUMMARY)

    assert_response :success
    assert_select "th", text: "101 - 103"
    assert_select "th", text: "201 - 202"
    # The counts upstream gets wrong: it reports 4 for the first range and 1 for
    # the last.
    assert_select "td[data-label=Count]", text: "3"
    assert_select "td[data-label=Count]", text: "2"
    # The roster's own rows are gone -- this is the other table, not both.
    assert_select "th", text: "102", count: 0
  end

  test "the view toggle carries the year and the filters both ways" do
    create_radio(barcode: "101", perm_assign: true)
    create_radio(barcode: "500", perm_assign: false)

    sign_in_as(@admin)
    get asset_management_radio_assets_path(year: Current.year, duration: "event")

    assert_response :success
    assert_select "a[href=?]",
                  asset_management_radio_assets_path(year: Current.year, duration: "event",
                                                     view: SUMMARY),
                  text: /Summarized View/

    get asset_management_radio_assets_path(year: Current.year, duration: "event", view: SUMMARY)

    assert_response :success
    assert_select "a[href=?]",
                  asset_management_radio_assets_path(year: Current.year, duration: "event"),
                  text: /Full Roster/
    # An Apply Filters from the summarized view has to come back to it. Scoped
    # to the filter panel and counted: the hero's two year selectors (desktop
    # and mobile) each emit the same hidden field, so an unscoped match passes
    # even with the filter form's own field deleted.
    assert_select "#radio-assets-filters-panel input[type=hidden][name=view][value=?]",
                  SUMMARY, count: 1
  end

  test "the roster does not emit the summary hidden field" do
    create_radio(barcode: "101")

    sign_in_as(@admin)
    get asset_management_radio_assets_path

    assert_response :success
    assert_select "input[type=hidden][name=view]", count: 0
  end

  test "the duration filter narrows the table and the stat boxes with it" do
    create_radio(barcode: "101", perm_assign: true)
    create_radio(barcode: "500", perm_assign: false)

    sign_in_as(@admin)
    get asset_management_radio_assets_path(duration: "shift")

    assert_response :success
    assert_select "th", text: /500/
    assert_select "th", text: /101/, count: 0
    assert_select "span", text: "Showing 1 of 2 radios"
    # Stats describe the filtered view, so the event count reads zero here.
    assert_select "div", text: /\A0\s*Event Radios\z/
    assert_select "div", text: /\A1\s*Shift Radios\z/
  end

  test "the description filter narrows the table" do
    create_radio(barcode: "101", description: "Ranger Event 26-065")
    create_radio(barcode: "500", description: "Ranger Shift 26-066")

    sign_in_as(@admin)
    get asset_management_radio_assets_path(description: "Ranger Event 26-065")

    assert_response :success
    assert_select "th", text: /101/
    assert_select "th", text: /500/, count: 0
    assert_select "span", text: "Showing 1 of 2 radios"
  end

  test "radios with no description are reachable through the Blank option" do
    create_radio(barcode: "101", description: nil)
    create_radio(barcode: "500", description: "Ranger Event 26-065")

    sign_in_as(@admin)
    get asset_management_radio_assets_path(description: Asset::BLANK_FILTER_VALUE)

    assert_response :success
    assert_select "th", text: /101/
    assert_select "th", text: /500/, count: 0
    assert_select "td[data-label=Description]", text: "—"
  end

  test "the barcode filter finds one radio across a paged roster" do
    (1..101).each { |number| create_radio(barcode: format("%04d", number)) }

    sign_in_as(@admin)
    get asset_management_radio_assets_path(barcode: "0101")

    assert_response :success
    # 0101 sits on page 2, so without the filter the reader could not see it
    # here at all.
    assert_select "th", text: "0101"
    assert_select "span", text: "Showing 1 of 101 radios"
  end

  test "the barcode filter matches any part of a barcode, ignoring case" do
    create_radio(barcode: "SAND5108")
    create_radio(barcode: "101")

    sign_in_as(@admin)
    get asset_management_radio_assets_path(barcode: "sand")

    assert_response :success
    assert_select "th", text: "SAND5108"
    assert_select "th", text: "101", count: 0
  end

  test "a barcode that matches nothing says so rather than showing everything" do
    create_radio(barcode: "101")

    sign_in_as(@admin)
    get asset_management_radio_assets_path(barcode: "nosuchbarcode")

    assert_response :success
    assert_select "th", text: "101", count: 0
    assert_select "body", text: /No #{Current.year} radios match these filters/
  end

  test "the description options are narrowed by the duration already chosen" do
    create_radio(barcode: "101", description: "Event only", perm_assign: true)
    create_radio(barcode: "500", description: "Shift only", perm_assign: false)

    sign_in_as(@admin)
    get asset_management_radio_assets_path(duration: "shift")

    assert_response :success
    # Offering the event-only block under Duration = Shift promises a roster the
    # choice cannot deliver.
    assert_select "select[name=description] option[value=?]", "Shift only"
    assert_select "select[name=description] option[value=?]", "Event only", count: 0
  end

  test "a description colliding with a filter sentinel is never offered" do
    # "all" is the filter-off sentinel and "Blank" the no-description one; an
    # option carrying either value is a choice that silently does nothing.
    create_radio(barcode: "101", description: "all")
    create_radio(barcode: "500", description: Asset::BLANK_FILTER_VALUE)
    create_radio(barcode: "900", description: "Ranger Event 26-065")

    sign_in_as(@admin)
    get asset_management_radio_assets_path

    assert_response :success
    assert_select "select[name=description] option[value=all]", count: 1
    assert_select "select[name=description] option[value=?]", Asset::BLANK_FILTER_VALUE, count: 0
    assert_select "select[name=description] option[value=?]", "Ranger Event 26-065"
  end

  test "the Blank option appears only when a radio really has no description" do
    create_radio(barcode: "101", description: "Ranger Event 26-065")

    sign_in_as(@admin)
    get asset_management_radio_assets_path
    assert_response :success
    assert_select "select[name=description] option[value=?]", Asset::BLANK_FILTER_VALUE, count: 0

    create_radio(barcode: "500", description: nil)
    get asset_management_radio_assets_path
    assert_response :success
    assert_select "select[name=description] option[value=?]", Asset::BLANK_FILTER_VALUE
  end

  test "a year holding assets but no radios says which year it fell back to" do
    create_radio(barcode: "101")
    Asset.create!(barcode: "GEAR-1", type: Asset::TYPE_GEAR, year: Current.year - 1)

    sign_in_as(@admin)
    get asset_management_radio_assets_path(year: Current.year - 1)

    assert_response :success
    assert_select "body", text: /No radios were recorded for #{Current.year - 1}/
    assert_select "th", text: /101/
  end

  test "a garbled year falls back without claiming a year was skipped" do
    create_radio(barcode: "101")

    sign_in_as(@admin)
    get asset_management_radio_assets_path(year: "not-a-year")

    assert_response :success
    assert_select "body", text: /No radios were recorded for/, count: 0
  end

  test "an unrecognized filter value shows everything" do
    create_radio(barcode: "101")

    sign_in_as(@admin)
    get asset_management_radio_assets_path(duration: "bogus", description: "never issued")

    assert_response :success
    assert_select "th", text: /101/
    assert_select "span", text: "Showing 1 of 1 radio"
  end

  test "the year selector and the filter chip each carry the other's state" do
    create_radio(barcode: "101", perm_assign: true)
    create_radio(barcode: "500", perm_assign: false)

    sign_in_as(@admin)
    get asset_management_radio_assets_path(duration: "event", view: SUMMARY)

    assert_response :success
    # The year selector submits its own bare GET, so it has to re-emit both.
    # hero_panel renders the selector twice (desktop and mobile), and each emits
    # its own keep: fields -- counted so that losing one emitter fails here
    # rather than being covered by the other, or by the filter form's own field.
    assert_select "input[type=hidden][name=duration][value=?]", "event", count: 2
    assert_select "input[type=hidden][name=view][value=?]", SUMMARY, count: 3
    # ...and the filter form has to re-emit the year.
    assert_select "#radio-assets-filters-panel input[type=hidden][name=year][value=?]",
                  Current.year.to_s, count: 1
    # Removing the chip keeps the year AND the summarized view. Scoped by
    # aria-label: "Clear All Filters" carries an identical href, so a bare href
    # match would pass even if the chip dropped both.
    assert_select "a[aria-label=?][href=?]",
                  "Remove filter: Duration: Event",
                  asset_management_radio_assets_path(year: Current.year, view: SUMMARY)
  end

  test "neither view repeats a DOM id" do
    # This page carries two forms over one set of params -- the year selector
    # and the filter bar -- so a hidden field defaulting its id from its name is
    # one rename away from colliding with the select of the same name.
    create_radio(barcode: "101", perm_assign: true)
    create_radio(barcode: "500", perm_assign: false)

    sign_in_as(@admin)

    get asset_management_radio_assets_path(duration: "event")
    assert_response :success
    assert_unique_dom_ids

    get asset_management_radio_assets_path(duration: "event", view: SUMMARY)
    assert_response :success
    assert_unique_dom_ids
  end

  test "a filter that matches nothing says so" do
    create_radio(barcode: "101", perm_assign: true)

    sign_in_as(@admin)
    get asset_management_radio_assets_path(duration: "shift")

    assert_response :success
    assert_select "body", text: /No #{Current.year} radios match these filters/
  end

  test "an empty inventory shows the no-records state" do
    sign_in_as(@admin)
    get asset_management_radio_assets_path

    assert_response :success
    assert_select "body", text: /No radios have been added to the inventory yet/
  end

  test "a malformed year param falls back instead of raising" do
    create_radio(barcode: "101")

    sign_in_as(@admin)

    get "/asset-management/radio-assets?year[]=#{Current.year}"
    assert_response :success
    assert_select "th", text: /101/

    get "/asset-management/radio-assets?year[bogus]=1"
    assert_response :success
  end

  test "the roster pages and clamps an out-of-range page number" do
    (1..101).each { |number| create_radio(barcode: format("%04d", number)) }

    sign_in_as(@admin)
    get asset_management_radio_assets_path

    assert_response :success
    assert_select "span", text: "Page 1 of 2"
    assert_select "th", text: "0001"
    assert_select "th", text: "0101", count: 0

    get asset_management_radio_assets_path(page: 2)
    assert_response :success
    assert_select "th", text: "0101"

    # Past the end clamps to the last page rather than showing nothing.
    get asset_management_radio_assets_path(page: 99)
    assert_response :success
    assert_select "span", text: "Page 2 of 2"

    get asset_management_radio_assets_path(page: 0)
    assert_response :success
    assert_select "span", text: "Page 1 of 2"
  end

  test "a barcode links to the record page, which offers a way back here" do
    radio = create_radio(barcode: "101", perm_assign: false)

    sign_in_as(@admin)
    get asset_management_radio_assets_path(duration: "shift")

    assert_response :success
    link = asset_management_record_path(radio, year: Current.year, duration: "shift",
                                               page: 1, type: Asset::TYPE_RADIO,
                                               origin: "radio-assets")
    assert_select "a[href=?]", link

    get link
    assert_response :success
    assert_select "a[href=?]", asset_management_radio_assets_path(year: Current.year,
                                                                 duration: "shift", page: 1),
                  text: /Radio assets/
  end

  test "editing a radio reached from this report cancels back to the radio inventory" do
    # type: rides along on the barcode link because Cancel and Delete key on it;
    # without it they land on the bare types index instead of the radio page.
    radio = create_radio(barcode: "101", perm_assign: false)

    sign_in_as(@editor)
    get edit_asset_management_record_path(radio, year: Current.year, duration: "shift",
                                                 page: 1, type: Asset::TYPE_RADIO,
                                                 origin: "radio-assets")

    assert_response :success
    # Scoped to the form: the sidebar carries its own link to the bare inventory
    # on every page in this namespace.
    assert_select "form a[href=?]",
                  asset_management_records_type_path(Asset::TYPE_RADIO, year: Current.year)
    assert_select "form a[href=?]", asset_management_records_path(year: Current.year), count: 0
  end

  test "the summarized view links a one-radio range to its record page" do
    radio = create_radio(barcode: "101")
    %w[500 501].each { |barcode| create_radio(barcode:) }

    sign_in_as(@admin)
    get asset_management_radio_assets_path(view: SUMMARY)

    assert_response :success
    # A single-radio range is labelled with the bare barcode, so it looks
    # exactly like a roster row and has to behave like one.
    assert_select "a[href=?]",
                  asset_management_record_path(radio, year: Current.year, view: SUMMARY, page: 1,
                                                      type: Asset::TYPE_RADIO,
                                                      origin: "radio-assets"),
                  text: "101"
    # A multi-radio range has no single record to open.
    assert_select "th", text: "500 - 501"
    assert_select "a", text: "500 - 501", count: 0
  end

  test "CSV export carries the roster columns and honors the filters" do
    create_radio(barcode: "101", description: "Ranger Event 26-065", perm_assign: true)
    create_radio(barcode: "500", description: "Ranger Shift 26-066", perm_assign: false)

    sign_in_as(@admin)
    get asset_management_radio_assets_path(format: :csv)

    assert_response :success
    assert_equal "text/csv", response.media_type
    assert_match(/#{Current.year}-radio-assets-report\.csv/, response.headers["Content-Disposition"])

    lines = response.body.lines.map(&:chomp)
    assert_equal "Barcode,Description,Duration", lines.first
    assert_equal 3, lines.size
    assert_includes response.body, "Ranger Event 26-065"

    # A filtered export needs its own filename, or the second download collides.
    get asset_management_radio_assets_path(duration: "shift", format: :csv)
    assert_response :success
    assert_equal 2, response.body.lines.size
    assert_includes response.body, "500"
    assert_match(/#{Current.year}-shift-radio-assets-report\.csv/, response.headers["Content-Disposition"])
  end

  test "CSV export of the summarized view carries the ranges and their counts" do
    %w[101 102 103].each { |barcode| create_radio(barcode:, description: "Ranger Event 26-065") }

    sign_in_as(@admin)
    get asset_management_radio_assets_path(view: SUMMARY, format: :csv)

    assert_response :success
    lines = response.body.lines.map(&:chomp)
    assert_equal "Barcode Range,Count,Description,Duration", lines.first
    assert_equal "101 - 103,3,Ranger Event 26-065,Event", lines.second
    assert_match(/#{Current.year}-summary-radio-assets-report\.csv/, response.headers["Content-Disposition"])
  end

  test "a description with slashes does not become a path in the export filename" do
    create_radio(barcode: "101", description: "Event | EXP 9/2 12:00")

    sign_in_as(@admin)
    get asset_management_radio_assets_path(description: "Event | EXP 9/2 12:00", format: :csv)

    assert_response :success
    disposition = response.headers["Content-Disposition"]
    assert_match(/#{Current.year}-description-event-exp-9-2-12-00-[0-9a-f]{6}-radio-assets-report\.csv/,
                 disposition)
  end

  test "a description that collides with another filter's value gets its own filename" do
    # Descriptions are free text, so one can read exactly like a duration or the
    # view marker. Unlabelled, ?description=Event would export under the same
    # name as ?duration=event while holding different rows.
    create_radio(barcode: "101", description: "Event", perm_assign: true)
    create_radio(barcode: "500", description: "Other", perm_assign: false)

    sign_in_as(@admin)

    get asset_management_radio_assets_path(duration: "event", format: :csv)
    assert_response :success
    by_duration = response.headers["Content-Disposition"]

    get asset_management_radio_assets_path(description: "Event", format: :csv)
    assert_response :success
    by_description = response.headers["Content-Disposition"]

    assert_not_equal by_duration, by_description
  end

  test "a description that parameterizes away still names a filtered export" do
    create_radio(barcode: "101", description: "———")
    create_radio(barcode: "500", description: "Ranger Event 26-065")

    sign_in_as(@admin)

    get asset_management_radio_assets_path(description: "———", format: :csv)
    assert_response :success
    assert_equal 2, response.body.lines.size
    # Pins the fallback itself, not merely that the name differs from the
    # unfiltered one: without it the slug is empty and the name still differs.
    assert_match(/#{Current.year}-description-other-[0-9a-f]{6}-radio-assets-report\.csv/,
                 response.headers["Content-Disposition"])
  end

  test "two descriptions that slug alike still get their own export filenames" do
    # parameterize is lossy: "Other" and "———" both reduce to "other" once the
    # empty result is defaulted, so the slug alone cannot separate them.
    create_radio(barcode: "101", description: "Other")
    create_radio(barcode: "500", description: "———")

    sign_in_as(@admin)

    get asset_management_radio_assets_path(description: "Other", format: :csv)
    assert_response :success
    by_other = response.headers["Content-Disposition"]

    get asset_management_radio_assets_path(description: "———", format: :csv)
    assert_response :success

    assert_not_equal by_other, response.headers["Content-Disposition"]
  end

  test "the export filename does not collide with the Asset Inventory radio export" do
    create_radio(barcode: "101")

    sign_in_as(@admin)
    get asset_management_radio_assets_path(format: :csv)
    assert_response :success
    report = response.headers["Content-Disposition"]

    get asset_management_records_type_path(Asset::TYPE_RADIO, year: Current.year, format: :csv)
    assert_response :success

    assert_not_equal report, response.headers["Content-Disposition"]
  end

  test "the Blank description means no description, as it does on the records page" do
    # Asset.apply_nullable_filter reads the sentinel as IS NULL, and `description`
    # rides between the two pages on the record Back link, so it cannot mean
    # something wider here.
    create_radio(barcode: "101", description: nil)
    create_radio(barcode: "500", description: Asset::BLANK_FILTER_VALUE)

    sign_in_as(@admin)
    get asset_management_radio_assets_path(description: Asset::BLANK_FILTER_VALUE)

    assert_response :success
    assert_select "th", text: /101/
    assert_select "th", text: /500/, count: 0
    assert_select "span", text: "Showing 1 of 2 radios"
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
        perm_assign: true,
        year: Current.year
      }.merge(attributes)
    )
  end

  def next_sequence
    @next_sequence = (@next_sequence || 0) + 1
  end
end
