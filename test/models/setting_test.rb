# frozen_string_literal: true

require "test_helper"

class SettingTest < ActiveSupport::TestCase
  include CacheTestHelper

  # Job workers share this cache with the web server in production, so a save
  # that leaves the old value cached is a save every worker misses.
  test "saving a setting clears its cached value" do
    with_cache_store do
      setting = Setting.find!(Setting::DAILY_REPORT_EMAIL)
      setting.update!(value: "old@example.com")
      assert_equal "old@example.com", Setting.get_value(Setting::DAILY_REPORT_EMAIL)

      setting.update!(value: "new@example.com")

      assert_equal "new@example.com", Setting.get_value(Setting::DAILY_REPORT_EMAIL)
    end
  end

  # A reader between the save and its commit still sees the old row, and caches
  # it again. The cache is cleared once the save commits, so that copy goes too.
  test "a value cached again before the save commits is gone once it does" do
    with_cache_store do |cache|
      setting = Setting.find!(Setting::DAILY_REPORT_EMAIL)
      setting.update!(value: "old@example.com")

      Setting.transaction do
        setting.update!(value: "new@example.com")
        cache.write(Setting::DAILY_REPORT_EMAIL, "old@example.com")
      end

      assert_equal "new@example.com", Setting.get_value(Setting::DAILY_REPORT_EMAIL)
    end
  end

  # A stored name the Clubhouse does not describe can never be read or changed
  # through the app, so the row is only clutter. Everything still in use has to
  # survive, which is what makes the cleanup safe to run.
  test "purge_undefined! deletes only the names the Clubhouse no longer knows" do
    # Written straight to the table: a name the Clubhouse does not describe is
    # exactly what it refuses to save, and these rows arrive from elsewhere.
    Setting.insert_all([{ name: "SomethingRetiredLongAgo", value: "leftover" }])
    kept = Setting.find_or_create_by!(name: Setting::DAILY_REPORT_EMAIL) { |s| s.value = "report@example.com" }

    assert_equal ["SomethingRetiredLongAgo"], Setting.purge_undefined!

    assert_not Setting.exists?(name: "SomethingRetiredLongAgo")
    assert Setting.exists?(name: kept.name)
  end

  # A filter used to keep only the matches already stored, so a setting nobody
  # had saved yet could not be found to set.
  test "find_for_query returns unstored matches with their defaults" do
    settings = Setting.find_for_query(filter: "allyoucaneat")

    assert_equal [Setting::ALL_YOU_CAN_EAT_EVENT_PERIOD_THRESHOLD, Setting::ALL_YOU_CAN_EAT_EVENT_WEEK_THRESHOLD],
      settings.map(&:name)
    assert settings.all?(&:new_record?)
    assert_equal ["0", "0"], settings.map(&:value)

    sandbox = Setting.find_for_query(filter: "BroadcastSMSSandbox").sole
    assert_predicate sandbox, :persisted?
  end

  # The broadcast test address is a pattern: anything the code could not turn
  # into one address per Ranger would quietly send nothing at all.
  test "the broadcast test address takes one address with a single ? before the @" do
    setting = Setting.find_or_initialize_by(name: Setting::BROADCAST_MAIL_TEST_ADDRESS)

    ["test+?@example.com", "?@example.com", "a?b@example.com", ""].each do |value|
      setting.value = value

      assert_predicate setting, :valid?, "#{value.inspect} should be accepted"
    end

    ["test@example.com", "test+??@example.com", "test+?@exa?mple.com",
     "a+?@example.com, b+?@example.com", "a+?@example.com\nb+?@example.com",
     "#{"x" * 60}+?@example.com"].each do |value|
      setting.value = value

      assert_not setting.valid?, "#{value.inspect} should be refused"
      assert_match(/single \?/, setting.errors[:value].join)
    end
  end
end
