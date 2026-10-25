class BackfillHandleReservationNormalizedHandleAndIndexes < ActiveRecord::Migration[8.1]
  class MigrationHandleReservation < ActiveRecord::Base
    self.table_name = "handle_reservation"
  end

  def up
    backfill_normalized_handles
    add_indexes
    report_duplicate_keys
  end

  def down
    remove_index :handle_reservation, name: "index_handle_reservation_on_expires_on" if index_exists?(:handle_reservation, :expires_on, name: "index_handle_reservation_on_expires_on")
    remove_index :handle_reservation, name: "index_handle_reservation_on_lookup_key" if index_exists?(:handle_reservation, [:normalized_handle, :reservation_type, :twii_year], name: "index_handle_reservation_on_lookup_key")
    remove_index :handle_reservation, name: "index_handle_reservation_on_type_and_year" if index_exists?(:handle_reservation, [:reservation_type, :twii_year], name: "index_handle_reservation_on_type_and_year")
  end

  private

  def backfill_normalized_handles
    say_with_time "Backfilling handle reservation normalized handles" do
      MigrationHandleReservation.find_each do |row|
        normalized_handle = normalize_word(row.handle)
        next if row.normalized_handle == normalized_handle

        row.update_columns(normalized_handle: normalized_handle)
      end
    end
  end

  def add_indexes
    add_index :handle_reservation, :expires_on, name: "index_handle_reservation_on_expires_on" unless index_exists?(:handle_reservation, :expires_on, name: "index_handle_reservation_on_expires_on")
    add_index :handle_reservation, [:normalized_handle, :reservation_type, :twii_year], name: "index_handle_reservation_on_lookup_key" unless index_exists?(:handle_reservation, [:normalized_handle, :reservation_type, :twii_year], name: "index_handle_reservation_on_lookup_key")
    add_index :handle_reservation, [:reservation_type, :twii_year], name: "index_handle_reservation_on_type_and_year" unless index_exists?(:handle_reservation, [:reservation_type, :twii_year], name: "index_handle_reservation_on_type_and_year")
  end

  def report_duplicate_keys
    duplicate_group_count = MigrationHandleReservation
      .where.not(normalized_handle: "")
      .group(:normalized_handle, :reservation_type, :twii_year)
      .having("COUNT(*) > 1")
      .count
      .count

    blank_normalized_count = MigrationHandleReservation.where(normalized_handle: "").count

    say "Handle reservation duplicate groups requiring manual review: #{duplicate_group_count}"
    say "Handle reservation rows still missing normalized_handle: #{blank_normalized_count}"
  end

  def normalize_word(word)
    return "" if word.blank?

    normalized = word.gsub(/&/, " and ")
    normalized = normalized.gsub(/©/, "@").unicode_normalize(:nfd).gsub(/[\u0300-\u036f]/, "")
    normalized.gsub(/\W/, "").downcase
  end
end
