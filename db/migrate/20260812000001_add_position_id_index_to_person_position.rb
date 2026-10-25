# Additive index on the Laravel-shared person_position table (same precedent as
# the 2026-07-25 report indexes and the trainer_status slot_id index): the
# table's only index is its composite primary key, which leads with person_id,
# so every "who holds this position" lookup scans all ~50,000 rows.
#
# The Position Sanity Checker asks that question seven times per board render
# -- the Shiny Penny holder set, both passes of Missing Positions, and the
# deactivated-position, team-membership and retired-account scans -- but the
# question is not new to that page; it is what PersonPosition.retrieve_grants
# and every position roster have always asked.
#
# if_not_exists, because the Laravel side may add the same index first.
class AddPositionIdIndexToPersonPosition < ActiveRecord::Migration[8.1]
  def change
    add_index :person_position, :position_id, if_not_exists: true
  end
end
