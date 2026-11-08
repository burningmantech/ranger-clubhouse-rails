# frozen_string_literal: true

# asset.expires_on was a date, so an asset could only expire at midnight, and
# the form promised 23:59 while has_expired? turned over at 00:00. A datetime
# lets the quartermaster say when. MariaDB turns each date into that day's
# 00:00:00, so every existing asset keeps expiring when it did. The down drops
# the time of day.
class RenameAssetExpiresOnToExpiresAt < ActiveRecord::Migration[8.1]
  def up
    change_column :asset, :expires_on, :datetime, precision: nil
    rename_column :asset, :expires_on, :expires_at
  end

  def down
    rename_column :asset, :expires_at, :expires_on
    change_column :asset, :expires_on, :date
  end
end
