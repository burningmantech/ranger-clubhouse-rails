# frozen_string_literal: true

require "test_helper"

# The guard is prepended into a throwaway migration class here, never into ActiveRecord::Migration,
# so no other test's migration runs through it. Its marker writes roll back with the test.
class DeployMigrationGuardTest < ActiveSupport::TestCase
  setup do
    @verbose_was = ActiveRecord::Migration.verbose
    ActiveRecord::Migration.verbose = false
    # Not @metadata: Minitest reports that one, and a parallel worker must marshal it to the parent.
    @internal_metadata = ActiveRecord::Base.connection_pool.internal_metadata
  end

  teardown do
    ActiveRecord::Migration.verbose = @verbose_was
    ActiveRecord::Base.lease_connection.execute("SET SESSION lock_wait_timeout = DEFAULT")
  end

  test "records the version before the migration runs and caps its wait for a table lock" do
    migration = guarded_migration(20261108000001)
    migration.migrate(:up)

    assert migration.ran
    assert_equal "20261108000001", @internal_metadata[DeployMigrationGuard::MARKER]
    assert_equal DeployMigrationGuard::LOCK_WAIT_SECONDS,
      ActiveRecord::Base.lease_connection.select_value("SELECT @@SESSION.lock_wait_timeout").to_i
  end

  test "refuses a migration an earlier run started and never finished" do
    @internal_metadata[DeployMigrationGuard::MARKER] = "20261108000001"
    migration = guarded_migration(20261108000001)

    error = assert_raises(DeployMigrationGuard::Interrupted) { migration.migrate(:up) }
    assert_includes error.message, "DELETE FROM ar_internal_metadata"
    assert_not migration.ran
  end

  test "runs the next migration once the one before it finished" do
    @internal_metadata[DeployMigrationGuard::MARKER] = "20261108000001"
    migration = guarded_migration(20261108000002)
    migration.migrate(:up)

    assert migration.ran
    assert_equal "20261108000002", @internal_metadata[DeployMigrationGuard::MARKER]
  end

  test "leaves a rollback alone" do
    @internal_metadata[DeployMigrationGuard::MARKER] = "20261108000001"
    migration = guarded_migration(20261108000001)
    migration.migrate(:down)

    assert migration.reverted
  end

  test "tries again while another run holds the migration lock" do
    attempts = 0
    _out, err = capture_io do
      DeployMigrationGuard.retrying(wait: 0) do
        attempts += 1
        raise ActiveRecord::ConcurrentMigrationError if attempts < 3
      end
    end

    assert_equal 3, attempts
    assert_includes err, "holds the lock"
  end

  test "a failure other than the lock is not tried again" do
    attempts = 0
    assert_raises(RuntimeError) do
      DeployMigrationGuard.retrying(wait: 0) do
        attempts += 1
        raise "migration failed"
      end
    end

    assert_equal 1, attempts
  end

  private

  def guarded_migration(version)
    Class.new(ActiveRecord::Migration[8.1]) do
      prepend DeployMigrationGuard
      attr_reader :ran, :reverted

      def up = @ran = true
      def down = @reverted = true
    end.new("GuardedMigration", version)
  end
end
