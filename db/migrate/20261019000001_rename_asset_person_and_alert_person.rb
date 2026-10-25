# frozen_string_literal: true

# The second deploy of the person_asset and person_alert renames: each view
# 20261018000001 and 000002 added goes, and its table takes the name, in one
# RENAME TABLE, so the code serving while this runs (which reads the new names
# through the views) finds a table there the moment the view is gone. Then the
# asset table's own index takes the new name, and the audit events
# (ApplicationRecord#record_audit names them after the table) written as
# asset-person-* go to person-asset-*: the old release wrote them until the
# first deploy's roll ended.
#
# A table already under the new name is left as it is: dev ran the earlier
# versions of 000001 and 000002, which renamed the tables. Each step skips
# what is done, so a run stopped partway can run again.
class RenameAssetPersonAndAlertPerson < ActiveRecord::Migration[8.1]
  TABLES = { "asset_person" => "person_asset", "alert_person" => "person_alert" }.freeze
  ASSET_INDEX = %w[asset_person_person_id_checked_out_index person_asset_person_id_checked_out_index].freeze
  EVENTS = %w[create update delete].freeze

  def up
    TABLES.each do |old_name, new_name|
      if view?(new_name)
        execute "RENAME TABLE #{new_name} TO #{new_name}_view, #{old_name} TO #{new_name}"
      end
      execute "DROP VIEW IF EXISTS #{new_name}_view"
    end
    rename_asset_index(*ASSET_INDEX)
    rename_events("asset-person", "person-asset")
  end

  # Back to the first deploy's state: each table under its old name, a view
  # under the new one.
  def down
    rename_asset_index(*ASSET_INDEX.reverse)
    TABLES.each do |old_name, new_name|
      next if view?(new_name)

      execute "RENAME TABLE #{new_name} TO #{old_name}"
      execute "CREATE VIEW #{new_name} AS SELECT * FROM #{old_name}"
    end
    rename_events("person-asset", "asset-person")
  end

  private

  def view?(name)
    select_value(<<~SQL) == "VIEW"
      SELECT table_type FROM information_schema.tables
       WHERE table_schema = DATABASE() AND table_name = #{quote(name)}
    SQL
  end

  def rename_asset_index(from, to)
    table = view?("person_asset") ? "asset_person" : "person_asset"
    rename_index table, from, to if index_name_exists?(table, from)
  end

  def rename_events(from, to)
    EVENTS.each do |operation|
      count = ActionLog.where(event: "#{from}-#{operation}").update_all(event: "#{to}-#{operation}")
      say "#{count} #{from}-#{operation} rows renamed"
    end
  end
end
