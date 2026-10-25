# frozen_string_literal: true

module BasicCacheHelper
  SITE_SETTING_PREFIX = "setting-"

  def self.included(base)
    base.send :include, CommonMethods
    base.send :extend, CommonMethods
  end

  module CommonMethods
    def cache_exist?(key)
      Rails.cache.exist?(key)
    end

    def cache_read(key)
      Rails.cache.read(key)
    end

    def cache_write(key, value)
      Rails.cache.write(key, value)
    end

    def cache_delete(key)
      Rails.cache.delete(key)
    end

    def cache_delete_matched(key)
      Rails.cache.delete_matched(key)
    end
  end
end
