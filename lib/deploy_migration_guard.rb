# frozen_string_literal: true

# What the migrate container in each deploy runs (bin/rails deploy:migrate, set by both workflows in
# .github/workflows/): db:migrate, made safe to run unattended on every task launch.
#
# - A migration that started and never finished is not run again on its own. ECS relaunches a task
#   whose migrate container failed, up to the circuit breaker's three, and MariaDB commits each
#   statement as it runs, so a second run would repeat whatever the first got through. Each migration
#   records its version in ar_internal_metadata before it starts; a run that finds that version still
#   pending refuses it until someone has repaired the database and deleted the row.
# - A statement waits LOCK_WAIT_SECONDS at most for a table's metadata lock. An ALTER queued behind
#   the serving release's open transaction holds up every new query on that table while it waits,
#   and MariaDB's own limit is a day.
# - A second runner waits for the first instead of failing: Rails takes its migration lock with a
#   zero timeout, and every failed launch counts toward the circuit breaker.
module DeployMigrationGuard
  MARKER = "deploy_migration_started"
  LOCK_WAIT_SECONDS = 30
  LOCK_RETRY_SECONDS = 10

  class Interrupted < StandardError; end

  # Runs the block (db:migrate) again for as long as another run holds the migration lock.
  def self.retrying(wait: LOCK_RETRY_SECONDS)
    yield
  rescue ActiveRecord::ConcurrentMigrationError
    warn "Another migration run holds the lock; trying again in #{wait} s"
    sleep wait
    retry
  end

  def migrate(direction)
    return super unless direction == :up

    connection = ActiveRecord::Tasks::DatabaseTasks.migration_connection
    metadata = connection.pool.internal_metadata
    if metadata[MARKER] == version.to_s
      raise Interrupted, "Migration #{version} started on an earlier run and never finished, so it is not run " \
        "again: MariaDB keeps whatever it got through. Repair the database by hand, then delete the marker " \
        "(DELETE FROM ar_internal_metadata WHERE `key` = '#{MARKER}') and deploy again."
    end

    connection.execute("SET SESSION lock_wait_timeout = #{LOCK_WAIT_SECONDS}")
    metadata[MARKER] = version.to_s
    super
  end
end
