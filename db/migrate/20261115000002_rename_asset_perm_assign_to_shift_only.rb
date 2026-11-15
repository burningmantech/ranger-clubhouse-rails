# frozen_string_literal: true

# asset.perm_assign said an asset was out for the event; the form now asks the
# opposite question, "Shift Only" (owner, 2026-11-15). The column is renamed
# and every value flipped, so each asset keeps the assignment it had. The
# default flips with it: a new asset was shift-only before and still is.
#
# One deploy: once this runs, the release still serving raises on perm_assign.
class RenameAssetPermAssignToShiftOnly < ActiveRecord::Migration[8.1]
  class MigrationAsset < ActiveRecord::Base
    self.table_name = "asset"
    self.inheritance_column = nil
  end

  def up
    rename_column :asset, :perm_assign, :shift_only
    flip(:shift_only)
    change_column :asset, :shift_only, :boolean, null: false, default: true,
                                                 comment: "checked out for one shift, not for the event?"
  end

  def down
    rename_column :asset, :shift_only, :perm_assign
    flip(:perm_assign)
    change_column :asset, :perm_assign, :boolean, null: false, default: false,
                                                  comment: "assigned \"permanently\" to a person?"
  end

  private

  def flip(column)
    MigrationAsset.reset_column_information
    MigrationAsset.update_all(column => Arel::Nodes::Not.new(MigrationAsset.arel_table[column]))
  end
end
