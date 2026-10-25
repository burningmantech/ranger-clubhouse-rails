# frozen_string_literal: true

require "test_helper"

class AssetManagement::SearchControllerTest < ActionDispatch::IntegrationTest
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

    get asset_management_search_path

    assert_redirected_to me_root_path
  end

  test "readers with any asset-viewing role can open the page" do
    gear(barcode: "GEAR-100")

    [@admin, @editor, @event_manager].each do |reader|
      sign_in_as(reader)

      get asset_management_search_path
      assert_response :success
      assert_select "h1", text: /Asset Search/
    end
  end

  test "a bare visit shows the form and no result" do
    gear(barcode: "GEAR-100")
    sign_in_as(@admin)

    get asset_management_search_path

    assert_response :success
    assert_select "input[name=barcode]"
    assert_select "body", text: /Scan or type a barcode above/
    assert_select "body", { text: /GEAR-100/, count: 0 }
  end

  test "a known barcode renders the asset and its history" do
    asset = gear(barcode: "GEAR-100", description: "Shade Structure", group_name: "Logistics")
    check_in(check_out(asset, @editor))
    sign_in_as(@admin)

    get asset_management_search_path(barcode: "GEAR-100")

    assert_response :success
    assert_select "body", text: /GEAR-100/
    assert_select "body", text: /Shade Structure/
    assert_select "body", text: /Logistics/
    assert_select "body", text: /Checkout History/
    assert_select "body", text: /#{@editor.callsign}/
  end

  test "an asset that is still out names the holder and offers check in" do
    asset = gear(barcode: "GEAR-100")
    check_out(asset, @editor)
    sign_in_as(@admin)

    get asset_management_search_path(barcode: "GEAR-100")

    assert_response :success
    assert_select "body", text: /Is Checked Out by #{@editor.callsign}/
    assert_select "a[href=?]", asset_management_search_check_in_path(asset), text: /Check In/
  end

  test "the barcode field clears after a hit and is kept after a miss" do
    gear(barcode: "GEAR-100")
    sign_in_as(@admin)

    # Cleared on a hit -- the field is autofocused and a scanner types at the
    # caret, so a leftover barcode would swallow the next scan.
    # #barcode is the search field itself -- the year selectors carry their own
    # hidden name="barcode" fields, which must keep the value either way.
    get asset_management_search_path(barcode: "GEAR-100")
    assert_response :success
    assert_select "input#barcode[value]", count: 0
    assert_select "input[type=hidden][name=barcode][value=?]", "GEAR-100"

    # Kept on a miss, so a typo can be corrected rather than retyped.
    get asset_management_search_path(barcode: "NOPE-999")
    assert_response :success
    assert_select "input#barcode[value=?]", "NOPE-999"
  end

  test "a barcode that is not a plain string is ignored" do
    gear(barcode: "GEAR-100")
    sign_in_as(@admin)

    get asset_management_search_path, params: { barcode: { a: "GEAR-100" } }

    assert_response :success
    assert_no_match(/=&gt;|=>/, response.body[/<h4.*?<\/h4>/m].to_s)
    assert_select "body", text: /Scan or type a barcode above/
  end

  test "check in is offered only on the row the action would close" do
    asset = gear(barcode: "GEAR-100")
    check_in(check_out(asset, @editor))
    # A second open row is not reachable through the app, but nothing in the
    # schema forbids one, and only a single row can be checked in.
    PersonAsset.create!(asset:, person_id: @admin.id, checked_out: Current.time,
                        check_out_person_id: @admin.id)
    PersonAsset.create!(asset:, person_id: @event_manager.id, checked_out: Current.time,
                        check_out_person_id: @admin.id)
    sign_in_as(@admin)

    get asset_management_search_path(barcode: "GEAR-100")

    assert_response :success
    assert_select "a[href=?]", asset_management_search_check_in_path(asset), count: 1
  end

  test "an asset that is checked in offers no check in control" do
    asset = gear(barcode: "GEAR-100")
    check_in(check_out(asset, @editor))
    sign_in_as(@admin)

    get asset_management_search_path(barcode: "GEAR-100")

    assert_response :success
    assert_select "a[href=?]", asset_management_search_check_in_path(asset), count: 0
    assert_select "body", { text: /Is Checked Out by/, count: 0 }
  end

  test "an asset with no checkouts reports an empty history" do
    gear(barcode: "GEAR-100")
    sign_in_as(@admin)

    get asset_management_search_path(barcode: "GEAR-100")

    assert_response :success
    assert_select "body", text: /No checkout history has been recorded/
  end

  test "an unknown barcode reports the miss" do
    gear(barcode: "GEAR-100")
    sign_in_as(@admin)

    get asset_management_search_path(barcode: "NOPE-999")

    assert_response :success
    assert_select "body", text: /NOPE-999 Was Not Found for 2026/
    assert_select "body", text: /No event year has an asset with this barcode/
  end

  test "a barcode carrying markup is escaped, not rendered" do
    gear(barcode: "GEAR-100")
    sign_in_as(@admin)

    get asset_management_search_path(barcode: "<script>alert(1)</script>")

    assert_response :success
    assert_no_match "<script>alert(1)</script>", response.body
    assert_match "&lt;script&gt;", response.body
  end

  test "a barcode belonging to another year links to that year" do
    gear(barcode: "GEAR-100")
    gear(barcode: "SHARED-1", year: 2024)
    sign_in_as(@admin)

    get asset_management_search_path(barcode: "SHARED-1", year: 2026)

    assert_response :success
    assert_select "body", text: /SHARED-1 Was Not Found for 2026/
    assert_select "a[href=?]",
                  asset_management_search_path(barcode: "SHARED-1", year: 2024),
                  text: "2024"
  end

  test "the same barcode in two years resolves to the selected year" do
    current = gear(barcode: "SHARED-1", description: "This Year")
    prior = gear(barcode: "SHARED-1", year: 2024, description: "Prior Year")
    sign_in_as(@admin)

    get asset_management_search_path(barcode: "SHARED-1", year: 2024)

    assert_response :success
    assert_select "body", text: /Prior Year/
    assert_select "body", { text: /This Year/, count: 0 }
    assert_select "a[href=?]",
                  asset_management_record_path(prior, year: 2024, origin: "search",
                                                      barcode: "SHARED-1"),
                  text: /Open Asset Record/
    assert_select "a[href=?]", asset_management_record_path(current), count: 0
  end

  test "a garbled year falls back to the default year" do
    gear(barcode: "GEAR-100")
    sign_in_as(@admin)

    get asset_management_search_path(barcode: "GEAR-100", year: { bogus: 1 })

    assert_response :success
    assert_select "body", text: /GEAR-100/
  end

  test "the year selector carries the barcode" do
    gear(barcode: "GEAR-100")
    gear(barcode: "GEAR-100", year: 2024)
    sign_in_as(@admin)

    get asset_management_search_path(barcode: "GEAR-100")

    assert_response :success
    assert_select "input[type=hidden][name=barcode][value=?]", "GEAR-100"
  end

  test "check in closes the open row and returns to the lookup" do
    asset = gear(barcode: "GEAR-100")
    row = check_out(asset, @editor)
    sign_in_as(@event_manager)

    patch asset_management_search_check_in_path(asset)

    assert_redirected_to asset_management_search_path(barcode: "GEAR-100", year: 2026)
    row.reload
    assert_not_nil row.checked_in
    assert_equal @event_manager.id, row.check_in_person_id
  end

  test "check in on an asset that is already in changes nothing" do
    asset = gear(barcode: "GEAR-100")
    row = check_in(check_out(asset, @editor))
    checked_in_at = row.checked_in
    sign_in_as(@admin)

    patch asset_management_search_check_in_path(asset)

    assert_redirected_to asset_management_search_path(barcode: "GEAR-100", year: 2026)
    assert_equal "Asset GEAR-100 is already checked in.", flash[:error]
    assert_equal checked_in_at.to_i, row.reload.checked_in.to_i
  end

  test "an unauthorized user cannot check an asset in" do
    asset = gear(barcode: "GEAR-100")
    row = check_out(asset, @editor)
    sign_in_as(@unauthorized)

    patch asset_management_search_check_in_path(asset)

    assert_redirected_to me_root_path
    assert_nil row.reload.checked_in
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

  def gear(**attributes)
    Asset.create!({ barcode: "ASSET-#{next_sequence}", type: Asset::TYPE_GEAR,
                    year: Current.year }.merge(attributes))
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
