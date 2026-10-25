# frozen_string_literal: true

require "test_helper"

class PositionCreditTest < ActiveSupport::TestCase
  include CacheTestHelper

  setup do
    @position = positions(:training_lead)
  end

  def build_credit(**attrs)
    PositionCredit.new({ position: @position,
                         start_time: "2026-08-25 00:00",
                         end_time: "2026-08-25 23:59",
                         credits_per_hour: 2.5,
                         description: "Morning" }.merge(attrs))
  end

  test "requires a description" do
    credit = build_credit(description: "")

    assert_not credit.valid?
    assert_includes credit.errors[:description], "Description can't be blank."
  end

  test "requires the ending time to be after the beginning time" do
    credit = build_credit(start_time: "2026-08-25 12:00", end_time: "2026-08-25 06:00")

    assert_not credit.valid?
    assert_includes credit.errors[:end_time], "The end time must be after the start time."
  end

  def cached_year?(store, year)
    store.exist?("position_credits/year/#{year}")
  end

  test "saving a credit drops the cached credits for its year" do
    credit = build_credit
    credit.save!

    with_cache_store do |store|
      PositionCredit.find_for_year_position(2026, @position.id)
      assert cached_year?(store, 2026)

      credit.update!(credits_per_hour: 4.0)

      assert_not cached_year?(store, 2026), "the 2026 cache should have been dropped"
    end
  end

  test "moving a credit across years drops both years" do
    credit = build_credit
    credit.save!

    with_cache_store do |store|
      PositionCredit.find_for_year_position(2026, @position.id)
      PositionCredit.find_for_year_position(2027, @position.id)
      assert cached_year?(store, 2026)
      assert cached_year?(store, 2027)

      credit.update!(start_time: "2027-08-25 00:00", end_time: "2027-08-25 23:59")

      assert_not cached_year?(store, 2026), "the year the credit left should have been dropped"
      assert_not cached_year?(store, 2027), "the year the credit moved to should have been dropped"
    end
  end

  test "destroying a credit drops the cached credits for its year" do
    credit = build_credit
    credit.save!

    with_cache_store do |store|
      PositionCredit.find_for_year_position(2026, @position.id)
      assert cached_year?(store, 2026)

      credit.destroy!

      assert_not cached_year?(store, 2026)
    end
  end

  test "a cached position's credits are read back without a query" do
    credit = build_credit
    credit.save!

    with_cache_store do
      PositionCredit.find_for_year_position(2026, @position.id)

      assert_no_queries do
        assert_equal [credit.id], PositionCredit.find_for_year_position(2026, @position.id).map(&:id)
      end
    end
  end

  test "warming records the positions with no credits, so no later lookup asks again" do
    credit = build_credit(start_time: "2027-08-25 00:00", end_time: "2027-08-25 23:59")
    credit.save!

    with_cache_store do
      PositionCredit.warm_bulk_year_cache(2026 => [@position.id], 2027 => [@position.id])

      assert_no_queries do
        PositionCredit.warm_bulk_year_cache(2026 => [@position.id], 2027 => [@position.id])
        assert_equal [], PositionCredit.find_for_year_position(2026, @position.id)
        assert_equal [credit.id], PositionCredit.find_for_year_position(2027, @position.id).map(&:id)
      end
    end
  end

  # Clubhouse 2 read a blank list as "the whole year". Here that is year_credits.
  test "warming no positions asks for nothing" do
    with_cache_store do
      assert_no_queries { PositionCredit.warm_year_cache(2026, []) }
    end
  end

  # A warm reads the year's entry to pick the positions it lacks, queries them,
  # and reads the entry again to write them back. Another request can cache one
  # of those positions while the query runs.
  test "warming replaces a position cached meanwhile instead of adding to it" do
    credit = build_credit
    credit.save!

    with_cache_store do |store|
      other_request = ->(*) { store.write("position_credits/year/2026", { @position.id => [credit] }) }
      ActiveSupport::Notifications.subscribed(other_request, "sql.active_record") do
        PositionCredit.warm_year_cache(2026, [@position.id])
      end

      assert_equal [credit.id], PositionCredit.find_for_year_position(2026, @position.id).map(&:id)
    end
  end
end
