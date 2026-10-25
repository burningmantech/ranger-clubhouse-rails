# frozen_string_literal: true

require "test_helper"

class AssetManagement::RecordsControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include ActiveSupport::Testing::TimeHelpers

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

  test "unauthorized user is redirected from asset inventory" do
    sign_in_as(@unauthorized)

    get asset_management_records_path

    assert_redirected_to me_root_path
  end

  test "event management can view assets but cannot access editor actions" do
    asset = create_asset(barcode: "RAD-100")

    sign_in_as(@event_manager)

    get asset_management_records_path
    assert_response :success
    assert_select "body", text: /Asset Inventory/

    get asset_management_records_type_path(asset.type, year: asset.year)
    assert_response :success

    get asset_management_record_path(asset, year: asset.year)
    assert_response :success

    get new_asset_management_record_path(year: Current.year)
    assert_redirected_to asset_management_records_path(year: Current.year)

    get edit_asset_management_record_path(asset, year: asset.year)
    assert_redirected_to asset_management_records_path(year: asset.year)
  end

  test "index renders the assets sidebar" do
    sign_in_as(@editor)

    get asset_management_records_path

    assert_response :success
    assert_select "aside[aria-label='Sidebar navigation'] a[href^='#{asset_management_records_path}']",
                  text: /Asset Inventory/
  end

  test "index renders empty state without a synthetic year selector" do
    sign_in_as(@editor)

    get asset_management_records_path

    assert_response :success
    assert_select "body", text: /No asset records have been added yet/
    assert_select "select[name='year']", count: 0
  end

  test "index year selector only shows years present in the asset table" do
    historical_year = Current.year - 1
    create_asset(barcode: "HIST-100", year: historical_year)

    sign_in_as(@editor)

    get asset_management_records_path

    assert_response :success
    assert_select "select[name='year'] option[value='#{historical_year}']", minimum: 1
    assert_select "select[name='year'] option[value='#{Current.year}']", count: 0
  end

  test "index drills down by type rather than listing records" do
    create_asset(barcode: "RAD-100", type: Asset::TYPE_RADIO)
    create_asset(barcode: "RAD-101", type: Asset::TYPE_RADIO)
    create_asset(barcode: "GEAR-100", type: Asset::TYPE_GEAR)

    sign_in_as(@editor)

    get asset_management_records_path

    assert_response :success
    # Barcodes belong to the drill-down page now, not the types index.
    assert_select "body", text: /RAD-100/, count: 0
    assert_select "body", text: /Showing 2 asset types with 3 records/
    assert_select "a[href=?]", asset_management_records_type_path(Asset::TYPE_RADIO, year: Current.year),
                  text: /Radio.*2 records/m
    assert_select "a[href=?]", asset_management_records_type_path(Asset::TYPE_GEAR, year: Current.year),
                  text: /Gear.*1 record/m
  end

  test "index badges the expired records for a type" do
    create_asset(barcode: "RAD-100", expires_on: Current.today - 1)
    create_asset(barcode: "RAD-101", expires_on: Current.today + 1)

    sign_in_as(@editor)

    get asset_management_records_path

    assert_response :success
    assert_select "a[href=?]", asset_management_records_type_path(Asset::TYPE_RADIO, year: Current.year),
                  text: /1 expired/
  end

  # asset.type is nullable in the Laravel-shared schema, and ui_drill_down_row
  # raises on a blank title. Write one past the Rails presence validation.
  test "an untyped record gets a reachable drill-down row" do
    untyped = create_asset(barcode: "MYSTERY")
    Asset.where(id: untyped.id).update_all(type: nil)

    sign_in_as(@editor)

    get asset_management_records_path
    assert_response :success
    assert_select "a[href=?]", asset_management_records_type_path("unspecified", year: Current.year),
                  text: /Unspecified/

    get asset_management_records_type_path("unspecified", year: Current.year)
    assert_response :success
    assert_select "body", text: /MYSTERY/
  end

  test "the type page narrows to its own type and carries the filters" do
    create_asset(barcode: "RAD-100", type: Asset::TYPE_RADIO, group_name: "Operations")
    create_asset(barcode: "RAD-101", type: Asset::TYPE_RADIO, group_name: "SITE")
    create_asset(barcode: "GEAR-100", type: Asset::TYPE_GEAR)

    sign_in_as(@editor)

    get asset_management_records_type_path(Asset::TYPE_RADIO, year: Current.year)
    assert_response :success
    assert_select "body", text: /RAD-100/
    assert_select "body", text: /GEAR-100/, count: 0
    assert_select "a[href=?]", asset_management_records_path(year: Current.year), text: /Asset Inventory/

    get asset_management_records_type_path(Asset::TYPE_RADIO, year: Current.year, group_name: "SITE")
    assert_response :success
    assert_select "body", text: /RAD-101/
    assert_select "body", text: /RAD-100/, count: 0
    assert_select "span", text: "Showing 1 of 2 records"
    # The type is the page, so its chip would have nowhere to land: only the
    # narrowing filters get one, and removing it keeps the year and the type.
    assert_select "a[aria-label=?][href=?]",
                  "Remove filter: Asset group: SITE",
                  asset_management_records_type_path(Asset::TYPE_RADIO, year: Current.year)
  end

  test "a type with no records for the year shows an empty state" do
    create_asset(barcode: "RAD-100", type: Asset::TYPE_RADIO)

    sign_in_as(@editor)

    get asset_management_records_type_path(Asset::TYPE_VEHICLE, year: Current.year)

    assert_response :success
    assert_select "body", text: /No vehicle records were found for #{Current.year}/
  end

  # The table is a shared partial with the Asset Search page, which renders it
  # with a Check In control; this page must keep rendering it without one.
  test "the record page renders the checkout history without a check in control" do
    asset = create_asset(barcode: "GEAR-100", type: Asset::TYPE_GEAR)
    PersonAsset.create!(asset:, person_id: @editor.id, checked_out: Current.time,
                        check_out_person_id: @admin.id)
    sign_in_as(@admin)

    get asset_management_record_path(asset, year: asset.year)

    assert_response :success
    assert_select "body", text: /Checkout History/
    assert_select "body", text: /#{@editor.callsign}/
    assert_select "body", text: /Still checked out/
    # The sidebar always links to Asset Search; what must be absent is a
    # check-in control, which only that page passes into the partial.
    assert_select "a[href*=?]", "check-in", count: 0
  end

  test "the record page reports an asset that has never been checked out" do
    asset = create_asset(barcode: "GEAR-100", type: Asset::TYPE_GEAR)
    sign_in_as(@admin)

    get asset_management_record_path(asset, year: asset.year)

    assert_response :success
    assert_select "body", text: /No checkout history has been recorded/
  end

  test "details and edit links return to the type page they came from" do
    asset = create_asset(barcode: "GEAR-100", type: Asset::TYPE_GEAR)

    sign_in_as(@editor)

    get asset_management_record_path(asset, year: asset.year, type: Asset::TYPE_GEAR)
    assert_response :success
    assert_select "a[href=?]", asset_management_records_type_path(Asset::TYPE_GEAR, year: asset.year),
                  text: /Gear assets/

    get edit_asset_management_record_path(asset, year: asset.year, type: Asset::TYPE_GEAR)
    assert_response :success
    assert_select "a[href=?]", asset_management_records_type_path(Asset::TYPE_GEAR, year: asset.year),
                  text: /Gear assets/
  end

  test "a record reached from assets outstanding still returns there" do
    asset = create_asset(barcode: "RAD-100")

    sign_in_as(@editor)

    get asset_management_record_path(asset, year: asset.year, type: Asset::TYPE_RADIO,
                                            origin: "outstanding")

    assert_response :success
    assert_select "a[href^=?]", asset_management_assets_outstanding_path, text: /Assets outstanding/
  end

  test "deleting a record returns to its type page" do
    asset = create_asset(barcode: "GEAR-100", type: Asset::TYPE_GEAR)

    sign_in_as(@editor)

    delete asset_management_record_path(asset, year: asset.year)

    assert_redirected_to asset_management_records_type_path(Asset::TYPE_GEAR, year: asset.year)
  end

  test "editor can batch create assets from a numeric barcode" do
    sign_in_as(@editor)

    assert_difference("Asset.count", 3) do
      post asset_management_records_path, params: {
        asset: {
          barcode: "ITEM007",
          copies: "3",
          type: Asset::TYPE_RADIO,
          description: "Portable",
          group_name: "Operations"
        }
      }
    end

    assert_redirected_to asset_management_records_type_path(Asset::TYPE_RADIO, year: Current.year)
    assert_equal %w[ITEM007 ITEM008 ITEM009], Asset.order(:barcode).pluck(:barcode)
  end

  test "the index csv exports the whole year" do
    create_asset(barcode: "RAD-100", type: Asset::TYPE_RADIO, perm_assign: true)
    create_asset(barcode: "GEAR-100", type: Asset::TYPE_GEAR, perm_assign: false)

    sign_in_as(@event_manager)

    get asset_management_records_path(format: :csv, year: Current.year)

    assert_response :success
    assert_includes response.headers["Content-Disposition"], "#{Current.year}-assets.csv"
    assert_includes response.body.lines.first, "Barcode,Type,Description,Assignment"
    assert_includes response.body, "RAD-100,Radio"
    assert_includes response.body, "GEAR-100,Gear"
  end

  test "the type csv exports the type label and the filtered scope" do
    create_asset(barcode: "RAD-100", type: Asset::TYPE_RADIO, perm_assign: true,
                 group_name: "Operations")
    create_asset(barcode: "RAD-101", type: Asset::TYPE_RADIO, perm_assign: true, group_name: "SITE")
    create_asset(barcode: "GEAR-100", type: Asset::TYPE_GEAR, perm_assign: false)

    sign_in_as(@event_manager)

    get asset_management_records_type_path(Asset::TYPE_RADIO, format: :csv, year: Current.year,
                                                             group_name: "SITE")

    assert_response :success
    assert_includes response.headers["Content-Disposition"], "#{Current.year}-radio-assets.csv"
    assert_includes response.body.lines.first, "Barcode,Type,Description,Assignment"
    assert_includes response.body, "RAD-101,Radio"
    assert_includes response.body, ",Event,"
    assert_not_includes response.body, "RAD-100"
    assert_not_includes response.body, "GEAR-100"
  end

  test "the report siblings' params do not draw nameless filter chips here" do
    # Needs a record of this type: an empty type page renders no filter bar at
    # all, and the chip assertion below would pass without proving anything.
    create_asset(barcode: "RAD-100")

    sign_in_as(@admin)

    # :outcome belongs to Asset History, :duration and :view to Radio Assets, and
    # :page to both. They are permitted only so records#show can rebuild each
    # report's Back link. None is a filter on this page or has a chip label.
    get asset_management_records_type_path(Asset::TYPE_RADIO, outcome: "returned", page: "2",
                                                             duration: "shift", view: "summary",
                                                             year: Current.year)

    assert_response :success
    assert_select "td", text: /RAD-100/
    assert_select "a[aria-label^=?]", "Remove filter: :", count: 0
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
        type: Asset::TYPE_RADIO,
        year: Current.year
      }.merge(attributes)
    )
  end

  def next_sequence
    @next_sequence = (@next_sequence || 0) + 1
  end
end
