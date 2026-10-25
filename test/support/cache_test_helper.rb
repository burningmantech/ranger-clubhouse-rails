# frozen_string_literal: true

# The test env uses :null_store, so swap in a real store to make cache behaviour
# observable.
#
# Use Rails' own writer. Do NOT swap the store with
# +Rails.define_singleton_method(:cache)+: Rails.cache is an attr_accessor on
# Rails' own singleton class, so redefining the reader replaces the real one for
# the rest of the process -- every later +Rails.cache = store+ becomes a silent
# no-op, and removing the method again leaves no reader at all. That made test
# results depend on which file ran first.
module CacheTestHelper
  def with_cache_store
    original = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    yield Rails.cache
  ensure
    Rails.cache = original
  end
end
