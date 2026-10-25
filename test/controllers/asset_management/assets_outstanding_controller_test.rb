# frozen_string_literal: true

require "test_helper"

class AssetManagement::AssetsOutstandingControllerTest < ActionDispatch::IntegrationTest
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

  test "unauthorized user is redirected" do
    sign_in_as(@unauthorized)

    get asset_management_assets_outstanding_path

    assert_redirected_to me_root_path
  end

  test "readers with any asset-viewing role can open the report" do
    check_out(create_asset(barcode: "RAD-100"), @editor)

    [@admin, @editor, @event_manager].each do |reader|
      sign_in_as(reader)

      get asset_management_assets_outstanding_path
      assert_response :success
      assert_select "body", text: /Assets Outstanding/
      assert_select "th", text: /RAD-100/
    end
  end

  test "only assets with an open checkout are listed" do
    check_out(create_asset(barcode: "RAD-OUT"), @editor)
    returned = check_out(create_asset(barcode: "RAD-BACK"), @editor)
    returned.update!(checked_in: Current.time, check_in_person_id: @admin.id)
    create_asset(barcode: "RAD-SHELF")

    sign_in_as(@admin)
    get asset_management_assets_outstanding_path

    assert_response :success
    assert_select "th", text: /RAD-OUT/
    assert_select "th", text: /RAD-BACK/, count: 0
    assert_select "th", text: /RAD-SHELF/, count: 0
  end

  test "the report is scoped to the selected year" do
    check_out(create_asset(barcode: "RAD-NOW"), @editor)
    check_out(create_asset(barcode: "RAD-THEN", year: Current.year - 1), @editor)

    sign_in_as(@admin)

    get asset_management_assets_outstanding_path(year: Current.year - 1)
    assert_response :success
    assert_select "th", text: /RAD-THEN/
    assert_select "th", text: /RAD-NOW/, count: 0

    # An unusable year falls back to the most recent year holding assets.
    get asset_management_assets_outstanding_path(year: "not-a-year")
    assert_response :success
    assert_select "th", text: /RAD-NOW/
  end

  test "the type filter narrows the table but not the totals" do
    check_out(create_asset(barcode: "RAD-1"), @editor)
    check_out(create_asset(barcode: "GEAR-1", type: Asset::TYPE_GEAR), @event_manager)

    sign_in_as(@admin)
    get asset_management_assets_outstanding_path(type: Asset::TYPE_GEAR)

    assert_response :success
    assert_select "th", text: /GEAR-1/
    assert_select "th", text: /RAD-1/, count: 0
    # Exact text, not a body-wide regex: "Showing 1 of 2 assets" as a substring
    # would also match "Showing 1 of 12 assets".
    assert_select "span", text: "Showing 1 of 2 assets"
    # Stat boxes report the whole year, not the filtered view. Anchored so a
    # regressed count ending in "2" (12, 22, 42) cannot satisfy it.
    assert_select "div", text: /\A2\s*Assets Outstanding\z/
  end

  test "the year selector and the filter chip each carry the other's state" do
    check_out(create_asset(barcode: "RAD-1"), @editor)
    check_out(create_asset(barcode: "GEAR-1", type: Asset::TYPE_GEAR), @event_manager)

    sign_in_as(@admin)
    get asset_management_assets_outstanding_path(type: Asset::TYPE_GEAR)

    assert_response :success
    # The year selector submits its own bare GET, so it has to re-emit the filter.
    assert_select "input[type=hidden][name=type][value=?]", Asset::TYPE_GEAR
    # ...and the filter form has to re-emit the year.
    assert_select "input[type=hidden][name=year][value=?]", Current.year.to_s
    # Removing the chip keeps the year. Scoped by aria-label: the "Clear all
    # filters" link carries an identical href, so a bare href match would pass
    # even if the chip dropped the year entirely.
    assert_select "a[aria-label=?][href=?]",
                  "Remove filter: Type: Gear",
                  asset_management_assets_outstanding_path(year: Current.year)
  end

  test "a reader who cannot open person pages sees plain callsigns" do
    check_out(create_asset(barcode: "RAD-1"), @admin)

    # EDIT_ASSETS reads this page but is not a person-page viewing role.
    sign_in_as(@editor)
    get asset_management_assets_outstanding_path

    assert_response :success
    assert_select "body", text: /#{@admin.callsign}/
    assert_select "a[href^='/person/']", count: 0
  end

  test "a NULL-typed asset does not hijack the unfiltered page" do
    check_out(create_asset(barcode: "RAD-1"), @editor)
    untyped = create_asset(barcode: "MYSTERY", type: Asset::TYPE_GEAR)
    # The Laravel-shared table permits a NULL type; write one the way an
    # external writer would, past the Rails presence validation.
    Asset.where(id: untyped.id).update_all(type: nil)
    check_out(untyped, @editor)

    sign_in_as(@admin)
    get asset_management_assets_outstanding_path

    assert_response :success
    assert_select "th", text: /RAD-1/
    assert_select "th", text: /MYSTERY/
    assert_select "span", text: "Showing 2 of 2 assets"
  end

  test "a malformed year param falls back instead of raising" do
    check_out(create_asset(barcode: "RAD-1"), @editor)

    sign_in_as(@admin)

    get "/asset-management/assets-outstanding?year[]=#{Current.year}"
    assert_response :success
    assert_select "th", text: /RAD-1/

    get "/asset-management/assets-outstanding?year[bogus]=1"
    assert_response :success
  end

  test "the default year is the newest one with something outstanding" do
    check_out(create_asset(barcode: "RAD-OUT", year: Current.year - 1), @editor)
    # Next season's inventory exists but nothing has gone out in it yet.
    create_asset(barcode: "RAD-SHELF", year: Current.year)

    sign_in_as(@admin)
    get asset_management_assets_outstanding_path

    assert_response :success
    assert_select "th", text: /RAD-OUT/
  end

  test "an unrecognized type filter shows everything" do
    check_out(create_asset(barcode: "RAD-1"), @editor)

    sign_in_as(@admin)
    get asset_management_assets_outstanding_path(type: "bogus")

    assert_response :success
    assert_select "th", text: /RAD-1/
    assert_select "span", text: "Showing 1 of 1 asset"
  end

  test "a year with nothing outstanding shows the all-clear" do
    create_asset(barcode: "RAD-SHELF")

    sign_in_as(@admin)
    get asset_management_assets_outstanding_path

    assert_response :success
    assert_select "body", text: /every asset has been checked back in/
  end

  test "an empty inventory shows the no-records state" do
    sign_in_as(@admin)
    get asset_management_assets_outstanding_path

    assert_response :success
    assert_select "body", text: /No asset records have been added yet/
  end

  test "a deleted holder is named by id rather than left blank" do
    holder = person(:prospective_ranger)
    person_asset = check_out(create_asset(barcode: "RAD-GONE"), holder)
    Person.where(id: holder.id).delete_all

    sign_in_as(@admin)
    get asset_management_assets_outstanding_path

    assert_response :success
    assert_select "body", text: /Deleted ##{person_asset.person_id}/

    get asset_management_assets_outstanding_path(format: :csv)
    assert_response :success
    assert_includes response.body, "Deleted ##{person_asset.person_id}"
  end

  test "an attachment is shown on the page and in the export" do
    # asset_attachment carries no auto-increment -- the id has to be supplied.
    attachment = AssetAttachment.create!(id: 9_001, parent_type: AssetAttachment::RADIO,
                                         description: "Shoulder Mic")
    check_out(create_asset(barcode: "RAD-1"), @editor).update!(attachment:)

    sign_in_as(@admin)
    get asset_management_assets_outstanding_path

    assert_response :success
    assert_select "td", text: /Shoulder Mic/

    get asset_management_assets_outstanding_path(format: :csv)
    assert_includes response.body, "Shoulder Mic"
  end

  test "CSV export carries the report columns and honors the filter" do
    check_out(create_asset(barcode: "RAD-1"), @editor)
    check_out(create_asset(barcode: "GEAR-1", type: Asset::TYPE_GEAR, description: "Trauma kit"),
              @event_manager)

    sign_in_as(@admin)
    get asset_management_assets_outstanding_path(format: :csv)

    assert_response :success
    assert_equal "text/csv", response.media_type
    assert_match(/#{Current.year}-assets-outstanding\.csv/, response.headers["Content-Disposition"])

    lines = response.body.lines.map(&:chomp)
    assert_equal "Barcode,Callsign,Type,Description,Attachment,Assignment,Checked Out,Checked Out By",
                 lines.first
    assert_equal 3, lines.size
    assert_includes response.body, "Trauma kit"
    assert_includes response.body, @editor.callsign

    # A filtered export needs its own filename, or the second download collides.
    get asset_management_assets_outstanding_path(type: Asset::TYPE_GEAR, format: :csv)
    assert_response :success
    assert_equal 2, response.body.lines.size
    assert_includes response.body, "GEAR-1"
    assert_match(/#{Current.year}-gear-assets-outstanding\.csv/,
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
        type: Asset::TYPE_RADIO,
        year: Current.year
      }.merge(attributes)
    )
  end

  def check_out(asset, holder)
    PersonAsset.create!(asset:, person_id: holder.id, checked_out: Current.time,
                        check_out_person_id: @admin.id)
  end

  def next_sequence
    @next_sequence = (@next_sequence || 0) + 1
  end
end
