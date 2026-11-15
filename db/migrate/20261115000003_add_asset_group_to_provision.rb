# frozen_string_literal: true

# A radio_group provision grants a radio from one radio asset group, so the
# provision points at that group. Null for every other provision type.
#
# Integer, not the bigint add_reference would pick: asset_group.id is a plain
# integer and a foreign key needs the two to match.
class AddAssetGroupToProvision < ActiveRecord::Migration[8.1]
  def change
    add_column :provision, :asset_group_id, :integer
    add_index :provision, :asset_group_id
    add_foreign_key :provision, :asset_group
  end
end
