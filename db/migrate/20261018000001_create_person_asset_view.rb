# frozen_string_literal: true

# asset_person joins the person_* family (person_slot, person_event, person_pog …),
# in two deploys, because the release serving while a deploy migrates still
# queries the old name (deploy/aws/deploy.sh migrates before it rolls).
#
# This one adds person_asset as a view over asset_person, which the old release
# keeps using as it is. The code that ships with it reads and writes through the
# view (ViewBackedTable on PersonAsset says what Rails cannot read off a view).
# 20261019000001 then swaps the view for the table itself, in one RENAME TABLE,
# while that code serves.
#
# Until 2026-10-19 this migration renamed the table, which broke every query
# of the release still serving; dev ran that version, so 20261019000001 finds
# a table there and leaves it.
class CreatePersonAssetView < ActiveRecord::Migration[8.1]
  def up
    execute "CREATE VIEW person_asset AS SELECT * FROM asset_person"
  end

  def down
    execute "DROP VIEW person_asset"
  end
end
