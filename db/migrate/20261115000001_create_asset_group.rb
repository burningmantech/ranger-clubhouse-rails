# frozen_string_literal: true

# asset.group_name was free text, so "Cmmd Ops" and "Command Operations" were
# two groups and nobody could retire or annotate one (owner, 2026-11-15). The
# names move to asset_group, one row per asset type and name, and each asset
# points at its row. group_name is dropped once every name has a row.
#
# asset_group.id is a plain integer because the owner asked for an integer
# asset.asset_group_id, and a foreign key needs the two to match.
#
# A group needs a type, so a name on an asset with no type (the Laravel-shared
# table allows one) has no group to go to: it is kept as a line in that asset's
# notes instead, and the down does not bring it back.
#
# The down puts each group's title back in group_name, cut to the old 25
# characters; a group's notes and its inactive flag do not survive it.
class CreateAssetGroup < ActiveRecord::Migration[8.1]
  class MigrationAsset < ActiveRecord::Base
    self.table_name = "asset"
    self.inheritance_column = nil
  end

  class MigrationAssetGroup < ActiveRecord::Base
    self.table_name = "asset_group"
    self.inheritance_column = nil
  end

  def up
    create_table :asset_group, id: :integer, charset: "utf8mb4", collation: "utf8mb4_unicode_ci" do |t|
      t.string :type, null: false
      t.string :title, null: false
      t.text :notes
      t.boolean :active, null: false, default: true
      t.index %i[type title], unique: true
    end

    add_column :asset, :asset_group_id, :integer
    add_index :asset, :asset_group_id
    add_foreign_key :asset, :asset_group

    MigrationAsset.reset_column_information
    groups, noted = move_group_names
    say "#{groups} asset groups created; #{noted} untyped assets kept their group name in their notes"

    remove_column :asset, :group_name
  end

  def down
    add_column :asset, :group_name, :string, limit: 25, after: :created_at

    MigrationAssetGroup.find_each do |group|
      MigrationAsset.where(asset_group_id: group.id).update_all(group_name: group.title[0, 25])
    end

    remove_foreign_key :asset, :asset_group
    remove_column :asset, :asset_group_id
    drop_table :asset_group
  end

  private

  # Answers [groups created, untyped assets whose name went to their notes].
  #
  # A title is the name stripped, and names that differ only by the spaces or
  # tabs around them, or by case, are one group: the group is looked up before
  # it is made, under the collation its unique index uses, so no two names can
  # collide on that index. A name that is nothing but whitespace is no name.
  def move_group_names
    named = MigrationAsset.where.not(group_name: nil)
    before = MigrationAssetGroup.count

    named.where.not(type: [nil, ""]).distinct.pluck(:type, :group_name).each do |type, name|
      title = name.strip
      next if title.empty?

      group = MigrationAssetGroup.find_or_create_by!(type:, title:)
      MigrationAsset.where(type:, group_name: name).update_all(asset_group_id: group.id)
    end

    untyped = named.where(type: [nil, ""]).select { |asset| asset.group_name.strip.present? }
    untyped.each do |asset|
      asset.update_columns(notes: [asset.notes.presence, "Asset group: #{asset.group_name.strip}"].compact.join("\n"))
    end

    [MigrationAssetGroup.count - before, untyped.size]
  end
end
