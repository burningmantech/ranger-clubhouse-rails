# frozen_string_literal: true

require "test_helper"

class VehicleEligibilityTest < ActiveSupport::TestCase
  include CacheTestHelper

  # Arbitrary person id; the cached paths below short-circuit before any DB access.
  PID = 987_654

  test "cache_key is namespaced per person AND year" do
    assert_equal "person-vehicle-5-2026", VehicleEligibility.cache_key(5, 2026)
  end

  # This file used to swap the store by redefining Rails.cache, which permanently
  # clobbered the real accessor and made every later `Rails.cache =` a no-op --
  # so whether another file's cache test passed depended on the run order.
  test "swapping the cache store leaves Rails.cache assignable afterwards" do
    original = Rails.cache
    with_cache_store { |store| assert_same store, Rails.cache }

    assert_same original, Rails.cache

    replacement = ActiveSupport::Cache::MemoryStore.new
    Rails.cache = replacement
    assert_same replacement, Rails.cache
  ensure
    Rails.cache = original
  end

  # The bug: the key omitted the year, so a result computed for one year was served for
  # another. With a per-year key, each year reads its own cached value.
  test "eligibility is cached per year, so one year does not poison another" do
    with_cache_store do |memory|
      memory.write("person-vehicle-#{PID}-2025", true)
      memory.write("person-vehicle-#{PID}-2026", false)

      assert_equal true, VehicleEligibility.is_person_eligible?(PID, 2025)
      assert_equal false, VehicleEligibility.is_person_eligible?(PID, 2026)
    end
  end

  test "purge_cache clears only the given year's entry" do
    with_cache_store do |memory|
      memory.write("person-vehicle-#{PID}-2025", true)
      memory.write("person-vehicle-#{PID}-2026", true)

      VehicleEligibility.purge_cache(PID, 2026)

      assert_nil memory.read("person-vehicle-#{PID}-2026")
      assert_equal true, memory.read("person-vehicle-#{PID}-2025")
    end
  end

  # MVRDeadline is admin-entered with no default. A blank or malformed value used
  # to raise ArgumentError out of Time.zone.parse, 500ing every signup for an
  # mvr_signup_eligible position and the whole vehicle dashboard.
  test "retrieve_mvr_deadline parses a configured MM-DD deadline" do
    with_mvr_deadline("08-01") do
      deadline, past = VehicleEligibility.retrieve_mvr_deadline

      assert_equal Current.year, deadline.year
      assert_equal 8, deadline.month
      assert_equal 1, deadline.day
      assert_includes [true, false], past
    end
  end

  test "retrieve_mvr_deadline reports no deadline when the setting is unset" do
    with_mvr_deadline(nil) do
      assert_equal [nil, false], VehicleEligibility.retrieve_mvr_deadline
    end
  end

  test "retrieve_mvr_deadline reports no deadline when the setting is blank" do
    with_mvr_deadline("") do
      assert_equal [nil, false], VehicleEligibility.retrieve_mvr_deadline
    end
  end

  # A deadline no one configured cannot have been missed — past must stay false,
  # or /me/vehicles raises a red "deadline passed" alarm over an empty date.
  test "retrieve_mvr_deadline reports no deadline when the setting is malformed" do
    with_mvr_deadline("not-a-date") do
      assert_equal [nil, false], VehicleEligibility.retrieve_mvr_deadline
    end
  end

  private

  def with_mvr_deadline(value)
    setting = Setting.find_or_create_by(name: Setting::MVR_DEADLINE)
    original = setting.value
    setting.update!(value:)
    Rails.cache.clear
    yield
  ensure
    setting.update!(value: original)
    Rails.cache.clear
  end
end
