# frozen_string_literal: true

require "test_helper"

class AssetGroupTest < ActiveSupport::TestCase
  setup do
    Current.reset
    @ops = AssetGroup.create!(type: Asset::TYPE_RADIO, title: "Command Operations", notes: "Main pool")
    @dupe = AssetGroup.create!(type: Asset::TYPE_RADIO, title: "Cmmd Ops", notes: "Typo of Command Operations")
    @gear = AssetGroup.create!(type: Asset::TYPE_GEAR, title: "Command Operations")
  end

  test "a title is unique within its type, and squished" do
    again = AssetGroup.new(type: Asset::TYPE_RADIO, title: "  Command   Operations ")

    assert_not again.valid?
    assert_equal "Command Operations", again.title
    assert_predicate @gear, :valid?
  end

  test "a type is one of the asset types, checked only when it changes" do
    odd = AssetGroup.new(type: "radios", title: "Typo")

    assert_not odd.valid?
    assert_includes odd.errors[:type], "Pick an asset type from the list."

    # As the backfill leaves a group made from a type no longer on the list.
    odd.save!(validate: false)
    assert odd.update(title: "Renamed", active: false)
  end

  test "an asset takes only a group of its own type" do
    asset = Asset.new(barcode: "R-1", type: Asset::TYPE_RADIO, year: 2026, asset_group: @gear)

    assert_not asset.valid?
    assert_includes asset.errors[:asset_group_id], "The asset group must be one of this asset type's groups."

    asset.asset_group = @ops
    assert_predicate asset, :valid?
  end

  test "a group in use keeps its type and cannot be deleted" do
    radio(@ops, "R-1")

    assert_not @ops.update(type: Asset::TYPE_GEAR, title: "Moved")
    assert_includes @ops.errors[:type], AssetGroup::TYPE_LOCKED

    assert_not @ops.reload.destroy
    assert_includes @ops.errors[:base], AssetGroup::IN_USE
    assert AssetGroup.exists?(@ops.id)

    assert @dupe.update(type: Asset::TYPE_GEAR)
    assert @dupe.destroy
  end

  test "merging moves the assets of every year, appends the notes and deletes the group" do
    this_year = radio(@dupe, "R-1", year: 2026)
    last_year = radio(@dupe, "R-1", year: 2025)
    kept = radio(@ops, "R-2")

    assert_difference -> { ActionLog.where(event: "asset-group-merge").count }, 1 do
      assert_equal 2, @dupe.merge_into!(@ops)
    end

    assert_not AssetGroup.exists?(@dupe.id)
    assert_equal [@ops.id] * 3, [this_year, last_year, kept].map { |asset| asset.reload.asset_group_id }
    assert_equal "Main pool\n\nTypo of Command Operations", @ops.reload.notes

    logged = ActionLog.where(event: "asset-group-merge").last.data
    assert_equal ["Cmmd Ops", "Command Operations", 2], logged.values_at("from_title", "into_title", "assets")
  end

  test "a group merges only into another group of its type" do
    radio(@dupe, "R-1")

    assert_raises(ArgumentError) { @dupe.merge_into!(@gear) }
    assert_raises(ArgumentError) { @dupe.merge_into!(@dupe) }
    assert AssetGroup.exists?(@dupe.id)
  end

  private

  def radio(group, barcode, year: 2026)
    Asset.create!(barcode:, type: Asset::TYPE_RADIO, year:, asset_group: group)
  end
end
