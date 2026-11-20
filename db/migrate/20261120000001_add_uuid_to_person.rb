# frozen_string_literal: true

# A public name for a person that cannot be guessed or counted through, for
# the voucher page (/voucher/:id). Version 7, so 74 of its bits are random.
#
# Nullable on purpose: during a rolling deploy the old containers still insert
# people without one, and a row with none simply has no voucher page.
class AddUuidToPerson < ActiveRecord::Migration[8.1]
  class MigrationPerson < ActiveRecord::Base
    self.table_name = "person"
  end

  def up
    # DDL is committed at once here, so a run that died in the backfill left
    # the column and index behind: the next run picks up where it stopped.
    add_column :person, :uuid, :string, limit: 36, if_not_exists: true
    add_index :person, :uuid, unique: true, if_not_exists: true

    MigrationPerson.where(uuid: nil).in_batches(of: 1000) do |batch|
      batch.pluck(:id).each do |id|
        MigrationPerson.where(id:).update_all(uuid: SecureRandom.uuid_v7)
      end
    end
  end

  def down
    remove_column :person, :uuid
  end
end
