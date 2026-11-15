# frozen_string_literal: true

require "application_system_test_case"

# The asset form's group select offers the groups of the chosen type. The
# server draws it for the type the page loaded with; asset_form_controller
# redraws it when the type changes.
class AssetFormGroupsTest < ApplicationSystemTestCase
  include TimesheetAdminTestHelper # ensure_role / grant_role

  setup do
    editor = person(:active_ranger)
    ensure_role(Role::EDIT_ASSETS, "Edit Assets")
    grant_role(editor, Role::EDIT_ASSETS)
    @site = AssetGroup.create!(type: Asset::TYPE_RADIO, title: "SITE")
    AssetGroup.create!(type: Asset::TYPE_RADIO, title: "Zendo", active: false)
    @sandman = AssetGroup.create!(type: Asset::TYPE_GEAR, title: "Sandman")
    @asset = Asset.create!(barcode: "RAD-100", type: Asset::TYPE_RADIO, year: Current.year, asset_group: @site)
    sign_in(editor)
  end

  test "changing the type redraws the groups, clears the choice and hides the field when there are none" do
    visit edit_asset_management_record_path(@asset)

    assert_equal ["", "SITE", "Zendo"], group_options
    assert_equal ["Active", "Inactive"], all("#asset_asset_group_id optgroup").map { |group| group[:label] }
    assert_equal @site.id.to_s, find("#asset_asset_group_id").value
    assert_checked_field "Shift Only"

    select "Gear", from: "Type"

    assert_equal ["", "Sandman"], group_options
    assert_equal "", find("#asset_asset_group_id").value

    select "Key", from: "Type"

    assert_no_selector "#asset_asset_group_id", visible: :visible

    select "Gear", from: "Type"
    select "Sandman", from: "Asset Group"
    uncheck "Shift Only"
    click_on "Save Asset"

    assert_text "Asset updated."
    assert_equal [Asset::TYPE_GEAR, @sandman.id, false], @asset.reload.values_at(:type, :asset_group_id, :shift_only)
  end

  # An asset with no type: its Type select falls to the first option, Radio,
  # and the groups have to follow what the select shows.
  test "the groups follow the type the select shows, not the one the server drew for" do
    @asset.update_columns(type: nil, asset_group_id: nil)

    visit edit_asset_management_record_path(@asset)

    assert_equal "Radio", find("#asset_type").find("option:checked").text
    assert_equal ["", "SITE", "Zendo"], group_options
    assert_selector "#asset_asset_group_id", visible: :visible
  end

  private

  def group_options
    all("#asset_asset_group_id option", visible: :all).map(&:text)
  end
end
