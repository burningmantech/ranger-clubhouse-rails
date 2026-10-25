# frozen_string_literal: true

require "test_helper"

# Reads config/database.yml through ActiveRecord's own configs. Nothing here
# opens a connection of its own, or loads, drops or empties anything.
class DatabaseConfigurationTest < ActiveSupport::TestCase
  include EnvTestHelper

  # A production database with no schema_migrations is a Clubhouse 2 restore,
  # and loading db/schema.rb into it drops every table the file defines and
  # creates it again empty. Without a path, db:migrate and db:prepare run the
  # migrations instead.
  test "production names no schema file for any of its databases" do
    with_env("SCHEMA" => nil) do
      configs = ActiveRecord::Base.configurations.configs_for(env_name: "production", include_hidden: true)

      assert_equal %w[primary cache queue cable], configs.map(&:name)
      configs.each do |db_config|
        assert_nil ActiveRecord::Tasks::DatabaseTasks.schema_dump_path(db_config), db_config.name
      end
    end
  end

  test "development and test still dump and load db/schema.rb" do
    with_env("SCHEMA" => nil) do
      %w[development test].each do |env_name|
        db_config = ActiveRecord::Base.configurations.configs_for(env_name:, name: "primary")

        assert_match %r{/db/schema\.rb\z}, ActiveRecord::Tasks::DatabaseTasks.schema_dump_path(db_config), env_name
      end
    end
  end

  # Solid Cable, Solid Queue and Solid Cache connect through their own configs,
  # which point at their environment's primary database. Seen by the db tasks,
  # they would make one database count as several: development would dump the
  # whole schema to a file per config and load each into the same database, and
  # bare db:rollback would refuse in development, production and training.
  test "development's db tasks see one database, through primary" do
    assert_db_tasks_see_primary_alone "development", %w[cable queue]
  end

  test "production's db tasks see one database, through primary" do
    assert_db_tasks_see_primary_alone "production", %w[cache queue cable]
  end

  test "training's db tasks see one database, through primary" do
    assert_db_tasks_see_primary_alone "training", %w[cache queue cable]
  end

  private

  # Compares whole hashes, not the database name: production's and training's
  # come from ENV variables nothing sets under test, so every name would be nil
  # and equal.
  def assert_db_tasks_see_primary_alone(env_name, shared_names)
    configurations = ActiveRecord::Base.configurations

    assert_equal %w[primary], configurations.configs_for(env_name:).map(&:name)
    assert_equal ["primary", *shared_names], configurations.configs_for(env_name:, include_hidden: true).map(&:name)

    primary = configurations.configs_for(env_name:, name: "primary")
    shared_names.each do |name|
      db_config = configurations.configs_for(env_name:, name:, include_hidden: true)

      assert_not db_config.database_tasks?, name
      assert_equal primary.configuration_hash, db_config.configuration_hash.except(:database_tasks), name
    end
  end
end
