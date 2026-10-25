# frozen_string_literal: true

require "test_helper"

class AssetManagement::Records::CreateFormTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  setup do
    travel_to Time.zone.local(2026, 4, 16, 12, 0, 0)
    Current.reset
    Current.person = person(:auditor_ranger)

    ActionLog.delete_all
    PersonAsset.delete_all
    Asset.delete_all
  end

  teardown do
    Current.reset
    travel_back
  end

  test "blank copies creates a single asset using defaults" do
    form = AssetManagement::Records::CreateForm.new(barcode: "RAD-100")

    assert_difference("Asset.count", 1) do
      assert form.save
    end

    asset = Asset.last
    assert_equal "RAD-100", asset.barcode
    assert_equal Asset::TYPE_RADIO, asset.type
    assert_equal Current.year, asset.year
    assert_equal "Operations", asset.group_name
  end

  test "multiple copies preserve zero padding" do
    form = AssetManagement::Records::CreateForm.new(barcode: "ITEM007", copies: "3")

    assert_difference("Asset.count", 3) do
      assert form.save
    end

    assert_equal %w[ITEM007 ITEM008 ITEM009], Asset.order(:barcode).pluck(:barcode)
  end

  test "multiple copies require a numeric barcode segment" do
    form = AssetManagement::Records::CreateForm.new(barcode: "RADIO", copies: "2")

    assert_no_difference("Asset.count") do
      assert_not form.save
    end

    assert_includes form.errors[:barcode], "The barcode must include a number when creating multiple copies."
  end

  test "batch creation rolls back if any asset is invalid" do
    create_asset(barcode: "DUP100")
    form = AssetManagement::Records::CreateForm.new(barcode: "DUP100", copies: "3")

    assert_no_difference("Asset.count") do
      assert_not form.save
    end

    assert_includes form.errors[:barcode], "Barcode has already been taken."
    assert_equal ["DUP100"], Asset.order(:barcode).pluck(:barcode)
  end

  private

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
