# frozen_string_literal: true

# alert_person was the last person-join table outside the person_* family
# (person_slot, person_event, person_asset …). Renamed in two deploys, as
# 20261018000001 says: this adds person_alert as a view over alert_person,
# and 20261019000001 swaps it for the table.
#
# Until 2026-10-19 this migration renamed the table; dev ran that version.
class CreatePersonAlertView < ActiveRecord::Migration[8.1]
  def up
    execute "CREATE VIEW person_alert AS SELECT * FROM alert_person"
  end

  def down
    execute "DROP VIEW person_alert"
  end
end
