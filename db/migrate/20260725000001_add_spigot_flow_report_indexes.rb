# Cover SpigotFlowReport's date-range scans. Both tables are shared with the
# legacy Laravel Clubhouse, so guard against the index arriving from that side.
class AddSpigotFlowReportIndexes < ActiveRecord::Migration[8.1]
  def change
    add_index :person_status, [:new_status, :created_at], if_not_exists: true
    add_index :prospective_application, :created_at, if_not_exists: true
  end
end
