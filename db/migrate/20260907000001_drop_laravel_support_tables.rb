# Laravel's own bookkeeping tables, carried over when the database was imported from
# Clubhouse 2. Rails keeps its migration history in schema_migrations, its cache and queue
# in the solid_cache / solid_queue databases, and its logins in sessions, so nothing here
# reads or writes any of these.
class DropLaravelSupportTables < ActiveRecord::Migration[8.1]
  def change
    %w[migrations cache cache_locks jobs failed_jobs personal_access_tokens].each do |table|
      drop_table table, if_exists: true
    end
  end
end
