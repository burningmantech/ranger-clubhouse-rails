# frozen_string_literal: true

require "test_helper"

# Nothing here runs mysqldump or mysql. What is checked is the refusals, which
# are the only things standing between a copy and the database it is made from.
class DatabaseDumpTest < ActiveSupport::TestCase
  include EnvTestHelper

  test "the working database cannot be the database it is built from" do
    error = assert_raises(DatabaseDump::Error) do
      DatabaseDump.create_working_database(DatabaseDump.primary_config[:database])
    end

    assert_match "cannot be the database it is built from", error.message
  end

  test "replacing this database has to be asked for by name" do
    target = DatabaseDump.primary_config[:database].to_s

    error = assert_raises(DatabaseDump::Error) { DatabaseDump.confirm_overwrite!("something else") }

    assert_match target, error.message
    assert DatabaseDump.confirm_overwrite!(target)
  end

  # The name goes into a statement that cannot take a placeholder, so anything
  # that is not plainly a name is refused rather than quoted.
  test "a database name that is not a name is refused" do
    ["rangers; drop database rangers", "rangers`", "with space", ""].each do |name|
      assert_raises(DatabaseDump::Error, "#{name.inspect} should be refused") do
        DatabaseDump.drop_database(name)
      end
    end
  end

  test "the clone source is read from the environment" do
    with_env("RANGER_DB_CLONE_FROM_DATABASE_NAME" => "somewhere_else") do
      assert_equal "somewhere_else", DatabaseDump.clone_source_config[:database]
    end
  end
end
