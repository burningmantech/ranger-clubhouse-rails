# frozen_string_literal: true

class PositionCredit < ApplicationRecord
  self.table_name = "position_credit"

  belongs_to :position

  validates :start_time, presence: true
  validates :end_time, presence: true
  validates :description, presence: true, length: { maximum: 25 }
  validates :credits_per_hour, presence: true, numericality: true
  validate :end_time_after_start_time

  attribute :credits_per_hour, :float

  scope :for_year, ->(year) { where(start_year: year).order(:start_time) }
  scope :for_year_position, ->(year, position_id) {
    where(position_id: position_id, start_year: year, end_year: year).order(:start_time)
  }

  after_commit :flush_year_caches

  CACHE_NAMESPACE = "position_credits"

  class << self
    # Find all credits for a given year with eager loaded relations
    def find_for_year(year)
      includes(:position).for_year(year)
    end

    # Find all the credits for a given year and position, cache the results.
    def find_for_year_position(year, position_id)
      cache_key = cache_key_for(year)
      cached = cache_store.read(cache_key) || {}

      return cached[position_id] if cached.key?(position_id)

      # Loaded: a cached Relation is only the query, run again on every read.
      rows = for_year_position(year, position_id).to_a
      cached[position_id] = rows
      cache_store.write(cache_key, cached)

      rows
    end

    # Warm the position credit cache with credits based on the given year and position ids.
    # A performance optimization to help compute_credits avoid extra lookups.
    def warm_year_cache(year, position_ids)
      warm_bulk_year_cache(year => position_ids)
    end

    # Warm the position credit cache with credits based on the given year and position ids.
    #
    # Each position asked for is stored whole, over whatever the entry holds for it:
    # its rows, or an empty list when it has none, so no later lookup asks again. The
    # entry is read once more before the write, and another request may have cached
    # the same position in between -- adding to its rows would price them twice.
    #
    # A blank list warms nothing. A caller wanting the whole year reads year_credits.
    def warm_bulk_year_cache(bulk_years)
      query = none
      find_ids_by_key = {}

      bulk_years.each do |year, position_ids|
        cache_key = cache_key_for(year)
        year_cache = cache_store.read(cache_key) || {}
        find_ids = position_ids.reject { |id| year_cache.key?(id) }

        next if find_ids.empty?

        find_ids_by_key[cache_key] = find_ids
        query = query.or(where(start_year: year, position_id: find_ids))
      end

      return if find_ids_by_key.empty?

      rows_by_key = query.order(:start_time).group_by { |row| cache_key_for(row.start_year) }

      find_ids_by_key.each do |cache_key, find_ids|
        year_cache = cache_store.read(cache_key) || {}
        find_ids.each { |id| year_cache[id] = [] }
        year_cache.merge!(rows_by_key.fetch(cache_key, []).group_by(&:position_id))
        cache_store.write(cache_key, year_cache)
      end
    end

    # Compute the credits for a position given the start and end times
    #
    # @param position_id [Integer] the id of the position
    # @param start_time [Integer] the starting time of the shift (Unix timestamp)
    # @param end_time [Integer] the ending time of the shift (Unix timestamp)
    # @param year [Integer] the year
    # @return [Float] earned credits
    def compute_credits(position_id, start_time, end_time, year)
      credits_for(find_for_year_position(year, position_id), start_time, end_time)
    end

    # The same sum, against a position's credit rates already in hand.
    #
    # compute_credits reads the whole year's rates back out of the cache on
    # every call, which a caller splitting a season's worth of shifts pays for
    # thousands of times over. Such a caller reads the year once with
    # year_credits and comes here with the rates for the position.
    def credits_for(credits, start_time, end_time)
      return 0.0 if credits.blank?

      credits.sum do |credit|
        minutes = minutes_overlap(start_time, end_time, credit.start_timestamp, credit.end_timestamp)
        minutes.positive? ? (minutes * credit.credits_per_hour / 60.0) : 0.0
      end
    end

    # Bulk compute the credits. This avoids the overhead with hitting the cache over, and over when iterating over
    # a large slot/timesheet set and magic accessor methods.
    #
    # The year's rates are read once, from the database; see year_credits.
    #
    # @param store_rows [Array] array of objects to store the credit value into with properties credits
    # @param rows [Array] array of objects with properties position
    # @param year [Integer] the year being computed
    # @param start_column [Symbol] the start timestamp (integer) column name in the rows
    # @param end_column [Symbol] the end timestamp (integer) column name in the rows
    def bulk_compute_credits(store_rows, rows, year, start_column, end_column)
      cached = year_credits(year)

      rows.each_with_index do |row, idx|
        # @
        credits = cached[row.position.id]
        store_row = store_rows[idx]

        if credits.blank?
          store_row.credits = 0.0
          next
        end

        store_row.credits = credits.sum do |credit|
          minutes = minutes_overlap(row.public_send(start_column), row.public_send(end_column),
                                    credit.start_timestamp, credit.end_timestamp)
          minutes.positive? ? (minutes * credit.credits_per_hour / 60.0) : 0.0
        end
      end
    end

    # A year's credits keyed by position, read from the database every time.
    #
    # Not from the year's cache entry. find_for_year_position and the warm_*
    # methods fill it a position at a time, so an entry that is there is rarely
    # the whole year -- and an evicted one is empty. Taken as the whole year,
    # it priced every position it lacked at 0.0: Hours & Credits showed a
    # different year total depending on which pages had been opened first.
    # Skipping it costs little: a hit deserializes a fresh copy of the whole
    # entry, and in production the store is a table in the same database.
    #
    # Keyed on start_year alone, as warm_bulk_year_cache is, so a row priced
    # here and the same row priced through a warmed cache agree about which
    # credits apply.
    def year_credits(year)
      for_year(year).group_by(&:position_id)
    end

    def cache_store
      Rails.cache
    end

    # Drops a year's cached credits so the next lookup reads the database.
    # Exact key only -- the production cache store has no delete_matched.
    def flush_year_cache(year)
      cache_store.delete(cache_key_for(year))
    end

    private

    def cache_key_for(year)
      "#{CACHE_NAMESPACE}/year/#{year}"
    end

    def minutes_overlap(start_a, end_a, start_b, end_b)
      overlap_start = [start_a, start_b].max
      overlap_end = [end_a, end_b].min

      return 0 if overlap_start >= overlap_end

      ((overlap_end - overlap_start) / 60.0).round
    end
  end

  def start_timestamp
    @start_timestamp ||= start_time.to_i
  end

  def end_timestamp
    @end_timestamp ||= end_time.to_i
  end

  private

  # Credit changes must not leave stale values in the per-year cache the
  # timesheet, slot, and report credit math reads from. A start time edited
  # across a year boundary invalidates both years.
  def flush_year_caches
    years = [start_time&.year]
    previous_start = saved_change_to_start_time&.first
    years << previous_start.year if previous_start

    years.compact.uniq.each { |year| self.class.flush_year_cache(year) }
  end

  def end_time_after_start_time
    return if end_time.blank? || start_time.blank?

    errors.add(:end_time, "The end time must be after the start time.") if end_time <= start_time
  end
end
