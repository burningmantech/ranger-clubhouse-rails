# frozen_string_literal: true

require "test_helper"
require Rails.root.join("db/migrate/20261115000001_create_asset_group.rb")
require Rails.root.join("db/migrate/20261115000002_rename_asset_perm_assign_to_shift_only.rb")

# The move of asset.group_name into asset_group has to run on a database that
# still has the column, so the test puts it back for its own run. Adding a
# column commits the test transaction, so this class runs without one and
# cleans up by hand, as CopyBouncingFlagsToEmailSuppressionTest does and at
# the same price.
class CreateAssetGroupTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  MIGRATION = CreateAssetGroup
  MigrationAsset = MIGRATION::MigrationAsset

  setup do
    clear_rows
    remove_name_column
    ActiveRecord::Migration.suppress_messages do
      ActiveRecord::Base.connection.add_column :asset, :group_name, :string, limit: 25
    end
    reset_asset_columns
  end

  teardown do
    clear_rows
    remove_name_column
  end

  test "each type and name becomes one group, whatever the case or the space around the name" do
    asset("R1", "radio", "SITE")
    asset("R2", "radio", " site")
    asset("R3", "radio", "SITE\t")
    asset("R4", "radio", "Operations")
    asset("G1", "gear", "Operations")
    asset("R5", "radio", nil)
    asset("R6", "radio", "")
    asset("R7", "radio", " \t")
    asset("U1", nil, "Lost & Found", notes: "No type")
    asset("U2", "", "Loaner")

    assert_equal [3, 2], MIGRATION.new.send(:move_group_names)

    groups = AssetGroup.order(:type, :title).pluck(:type, :title, :active, :notes)
    assert_equal [["gear", "Operations", true, nil], ["radio", "Operations", true, nil], ["radio", "SITE", true, nil]],
                 groups

    site = AssetGroup.find_by!(type: "radio", title: "SITE").id
    assert_equal [site] * 3, group_ids("R1", "R2", "R3")
    assert_equal [AssetGroup.find_by!(type: "radio", title: "Operations").id], group_ids("R4")
    assert_equal [AssetGroup.find_by!(type: "gear").id], group_ids("G1")
    assert_equal [nil] * 5, group_ids("R5", "R6", "R7", "U1", "U2")

    assert_equal ["No type\nAsset group: Lost & Found", "Asset group: Loaner"],
                 MigrationAsset.where(barcode: %w[U1 U2]).order(:barcode).pluck(:notes)

    assert_equal 0, MIGRATION.new.send(:move_group_names).first, "a second run makes no group twice"
  end

  test "the shift_only flip turns every value over" do
    asset("R1", "radio", nil, shift_only: true)
    asset("R2", "radio", nil, shift_only: false)

    RenameAssetPermAssignToShiftOnly.new.send(:flip, :shift_only)

    assert_equal [false, true], MigrationAsset.order(:barcode).pluck(:shift_only)
  end

  private

  def asset(barcode, type, group_name, **attributes)
    MigrationAsset.create!(barcode:, type:, group_name:, year: 2026, **attributes)
  end

  def group_ids(*barcodes)
    barcodes.map { |barcode| MigrationAsset.find_by!(barcode:).asset_group_id }
  end

  def clear_rows
    PersonAsset.delete_all
    Asset.delete_all
    AssetGroup.delete_all
  end

  def remove_name_column
    connection = ActiveRecord::Base.connection
    return unless connection.column_exists?(:asset, :group_name)

    ActiveRecord::Migration.suppress_messages { connection.remove_column :asset, :group_name }
    reset_asset_columns
  end

  # Three classes read the asset table and each caches its columns.
  def reset_asset_columns
    [MigrationAsset, RenameAssetPermAssignToShiftOnly::MigrationAsset, Asset].each(&:reset_column_information)
  end
end
