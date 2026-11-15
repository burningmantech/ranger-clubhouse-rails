# frozen_string_literal: true

require "test_helper"

class AssetManagement::GroupsControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper

  setup do
    Rails.cache.clear
    Current.reset

    @editor = person(:active_ranger)
    @event_manager = person(:echelon_ranger)
    @unauthorized = person(:ranger_with_custom_gender)

    ensure_role(Role::EDIT_ASSETS, "Edit Assets")
    ensure_role(Role::EVENT_MANAGEMENT, "Event Management")
    ensure_role(Role::TRAINER, "Trainer")

    grant_role(@editor, Role::EDIT_ASSETS)
    grant_role(@event_manager, Role::EVENT_MANAGEMENT)
    grant_role(@unauthorized, Role::TRAINER)

    @ops = AssetGroup.create!(type: Asset::TYPE_RADIO, title: "Command Operations")
    @dupe = AssetGroup.create!(type: Asset::TYPE_RADIO, title: "Cmmd Ops", active: false, notes: "A typo")
    @gear = AssetGroup.create!(type: Asset::TYPE_GEAR, title: "Sandman")
  end

  teardown do
    Current.reset
    Rails.cache.clear
  end

  test "the list is closed to a person with no asset role" do
    sign_in_as(@unauthorized)

    get asset_management_groups_path

    assert_redirected_to me_root_path
  end

  test "a reader sees the groups by type and no way to change them" do
    radio(@dupe, "R-1")
    sign_in_as(@event_manager)

    get asset_management_groups_path

    assert_response :success
    assert_select "[role=heading]", text: /Radio/
    assert_select "[role=heading]", text: /Gear/
    assert_select "tr", text: /Cmmd Ops.*Inactive.*1.*A typo/m
    assert_select "tr", text: /Command Operations.*Active.*0/m
    assert_select "a[href=?]", new_asset_management_group_path, count: 0
    assert_select "a[href=?]", edit_asset_management_group_path(@ops), count: 0

    get edit_asset_management_group_path(@ops)
    assert_redirected_to asset_management_groups_path

    post merge_asset_management_group_path(@dupe), params: { target_id: @ops.id }
    assert_redirected_to asset_management_groups_path
    assert AssetGroup.exists?(@dupe.id)
  end

  test "an editor adds a group, and a repeated title is refused" do
    sign_in_as(@editor)

    get new_asset_management_group_path
    assert_response :success

    assert_difference "AssetGroup.count", 1 do
      post asset_management_groups_path,
           params: { asset_group: { type: Asset::TYPE_VEHICLE, title: "Gerlach Patrol", notes: "Town fleet", active: "1" } }
    end
    assert_redirected_to asset_management_groups_path
    assert_equal ["Gerlach Patrol", "Town fleet", true],
                 AssetGroup.find_by!(type: Asset::TYPE_VEHICLE).values_at(:title, :notes, :active)

    assert_no_difference "AssetGroup.count" do
      post asset_management_groups_path, params: { asset_group: { type: Asset::TYPE_GEAR, title: "Sandman" } }
    end
    assert_response :unprocessable_entity

    assert_no_difference "AssetGroup.count" do
      post asset_management_groups_path, params: { asset_group: { type: "radios", title: "Typo" } }
    end
    assert_response :unprocessable_entity
  end

  test "an editor retires a group, and its type is locked while assets use it" do
    radio(@ops, "R-1")
    sign_in_as(@editor)

    get edit_asset_management_group_path(@ops)
    assert_response :success
    assert_select "select[name=?][disabled]", "asset_group[type]"
    assert_select "a[href=?]", merge_asset_management_group_path(@ops)

    patch asset_management_group_path(@ops), params: { asset_group: { title: "Command Ops", active: "0" } }
    assert_redirected_to asset_management_groups_path
    assert_equal ["Command Ops", false, Asset::TYPE_RADIO], @ops.reload.values_at(:title, :active, :type)

    patch asset_management_group_path(@ops), params: { asset_group: { type: Asset::TYPE_GEAR } }
    assert_response :unprocessable_entity
    assert_equal Asset::TYPE_RADIO, @ops.reload.type

    get edit_asset_management_group_path(@gear)
    assert_select "select[name=?][disabled]", "asset_group[type]", count: 0
  end

  test "an unused group deletes and a used one is refused" do
    radio(@ops, "R-1")
    sign_in_as(@editor)

    delete asset_management_group_path(@ops)
    assert_redirected_to edit_asset_management_group_path(@ops)
    assert_equal AssetGroup::IN_USE, flash[:error]
    assert AssetGroup.exists?(@ops.id)

    delete asset_management_group_path(@gear)
    assert_redirected_to asset_management_groups_path
    assert_not AssetGroup.exists?(@gear.id)
  end

  test "an editor merges a group into another of its type" do
    asset = radio(@dupe, "R-1")
    sign_in_as(@editor)

    get merge_asset_management_group_path(@dupe)
    assert_response :success
    assert_select "select[name=target_id] option[value=?]", @ops.id.to_s, text: "Command Operations"
    assert_select "select[name=target_id] option[value=?]", @gear.id.to_s, count: 0
    assert_select "select[name=target_id] option[value=?]", @dupe.id.to_s, count: 0

    post merge_asset_management_group_path(@dupe), params: { target_id: @ops.id }

    assert_redirected_to asset_management_groups_path
    assert_equal "Cmmd Ops merged into Command Operations. 1 asset moved.", flash[:success]
    assert_equal @ops.id, asset.reload.asset_group_id
    assert_not AssetGroup.exists?(@dupe.id)
  end

  test "a merge that cannot finish says so and changes nothing" do
    asset = radio(@dupe, "R-1")
    @ops.update_columns(notes: "x" * 65_530)
    sign_in_as(@editor)

    post merge_asset_management_group_path(@dupe), params: { target_id: @ops.id }

    assert_redirected_to merge_asset_management_group_path(@dupe)
    assert_match(/The merge could not finish and nothing was changed\./, flash[:error])
    assert_equal @dupe.id, asset.reload.asset_group_id
    assert AssetGroup.exists?(@dupe.id)
  end

  test "a merge into another type, or into itself, is refused" do
    radio(@dupe, "R-1")
    sign_in_as(@editor)

    [@gear.id, @dupe.id, ""].each do |target_id|
      post merge_asset_management_group_path(@dupe), params: { target_id: }

      assert_redirected_to merge_asset_management_group_path(@dupe)
    end
    assert AssetGroup.exists?(@dupe.id)

    get merge_asset_management_group_path(@gear)
    assert_response :success
    assert_select "select[name=target_id]", count: 0
    assert_select "body", text: /nothing to merge it into/
  end

  private

  def radio(group, barcode)
    Asset.create!(barcode:, type: Asset::TYPE_RADIO, year: Current.year, asset_group: group)
  end
end
