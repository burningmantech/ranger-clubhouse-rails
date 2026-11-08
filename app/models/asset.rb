# frozen_string_literal: true

class Asset < ApplicationRecord
  self.table_name = "asset"
  self.audit_model = true
  self.inheritance_column = :none

  BLANK_FILTER_VALUE = "Blank"
  BARCODE_SEGMENT_PATTERN = /\A(.*?)(\d+)(\D*)\z/

  # A typed expiry takes the calendar's shape: a date, a date and HH:MM
  # ("2026-09-15 14:30", or "2026-09-15T14:30" from a phone), or the
  # "2026-09-15 14:30:00 -0700" an edit page holds without JavaScript.
  # Time.zone.parse guesses at anything else ("9/10/26" is the year 9), and
  # MariaDB answers a five-digit year with a 500.
  EXPIRES_AT_FORMAT = /\A(\d{4})-(\d{2})-(\d{2})(?:[ T](\d{2}):(\d{2})(?::00(?: [+-]\d{4})?)?)?\z/
  EXPIRES_AT_UNREADABLE = "The expiration is not a date and time we could read. Pick one from the calendar."

  TYPE_GEAR = "gear"
  TYPE_RADIO = "radio"
  TYPE_TEMP_ID = "temp-id"
  TYPE_DESKTOP_RADIO = "desktop-radio"
  TYPE_MOBILE_RADIO = "mobile-radio"
  TYPE_RADIO_CHARGER = "radio-charger"

  TYPE_AMBER = "amber"
  TYPE_KEY = "key"
  TYPE_VEHICLE = "vehicle"

  has_many :asset_history, -> { order(:checked_out) },
           class_name: "PersonAsset",
           foreign_key: :asset_id,
           inverse_of: :asset,
           dependent: :delete_all

  has_one :checked_out, -> { where(checked_in: nil) },
          class_name: "PersonAsset",
          foreign_key: :asset_id,
          inverse_of: :asset

  validates :barcode, presence: true, length: { maximum: 25 }, uniqueness: { scope: :year }
  validates :group_name, length: { maximum: 25 }, allow_nil: true
  validates :description, length: { maximum: 64 }, allow_nil: true
  validates :type, presence: true
  validates :year, presence: true, numericality: { only_integer: true }
  validate :expires_at_is_readable

  # The same rule as #has_expired?, for a whole relation: an expiry that has
  # arrived has expired, and no expiry never does.
  scope :expired, -> { where(expires_at: ..Current.time) }
  scope :not_expired, -> { where(expires_at: nil).or(where.not(expires_at: ..Current.time)) }

  before_validation :normalize_optional_fields

  class << self
    def find_for_query(query = {})
      params = (query || {}).to_h.with_indifferent_access
      scope = where(year: params[:year].presence || Current.year)

      scope = scope.where(barcode: params[:barcode]) if params[:barcode].present?
      scope = apply_exclude_filter(scope, params[:exclude])
      scope = apply_exact_filter(scope, :type, params[:type])
      scope = apply_nullable_filter(scope, :description, params[:description])
      scope = apply_nullable_filter(scope, :order_number, params[:order_number])
      scope = apply_nullable_filter(scope, :entity_assignment, params[:entity_assignment])
      scope = apply_nullable_filter(scope, :group_name, params[:group_name])
      scope = apply_expire_filter(scope, params[:expire])

      if query_flag?(params, :checked_out)
        scope = scope.where(open_checkout_exists)
                     .includes(checked_out: [:person, :check_out_person, :attachment])
      elsif query_flag?(params, :include_history)
        scope = scope.includes(asset_history: [:person, :check_out_person, :check_in_person, :attachment])
      end

      natural_sort(scope.load)
    end

    def find_by_barcode_year(barcode, year)
      find_by(barcode:, year:)
    end

    alias_method :findForQuery, :find_for_query
    alias_method :findByBarcodeYear, :find_by_barcode_year

    # Whether typed text is an expiry the form may store: blank, or the
    # calendar's shape naming a real date and time in years the column holds.
    # A time set in code is not typed and needs no check.
    def readable_expiry?(value)
      return true unless value.is_a?(String)
      return true if value.blank?

      match = EXPIRES_AT_FORMAT.match(value.strip)
      return false unless match

      year, month, day, hour, minute = match.captures.map(&:to_i)
      year >= 1000 && Date.valid_date?(year, month, day) && hour < 24 && minute < 60
    end

    private

    def query_flag?(params, key)
      return false unless params.key?(key)

      ActiveModel::Type::Boolean.new.cast(params[key])
    end

    def apply_exact_filter(scope, column, value)
      return scope if value.blank? || value.to_s == "all"

      scope.where(column => value)
    end

    # `type != 'radio'` is NULL-unsafe: the Laravel-shared table permits a NULL
    # type, and such a row satisfies neither side of the comparison, so it would
    # vanish from a report that only meant to drop some other type.
    def apply_exclude_filter(scope, value)
      return scope if value.blank?

      type = arel_table[:type]
      scope.where(type.not_eq(value).or(type.eq(nil)))
    end

    def apply_nullable_filter(scope, column, value)
      return scope if value.blank? || value.to_s == "all"

      if value == BLANK_FILTER_VALUE
        scope.where(column => nil)
      else
        scope.where(column => value)
      end
    end

    def apply_expire_filter(scope, value)
      return scope if value.blank? || value.to_s == "all"

      case value.to_s
      when "expired"
        scope.expired
      when "not-expired"
        scope.not_expired
      else
        # A whole day in Clubhouse time, the day each row prints, as the
        # scheduling pages' day filters do.
        scope.where(expires_at: Date.iso8601(value.to_s).all_day)
      end
    rescue ArgumentError
      scope.none
    end

    def open_checkout_exists
      PersonAsset.where("person_asset.asset_id = asset.id")
                 .where(checked_in: nil)
                 .arel
                 .exists
    end

    def natural_sort(records)
      Array(records).sort_by { |asset| natural_barcode_key(asset.barcode) }
    end

    def natural_barcode_key(barcode)
      value = barcode.to_s
      matches = value.match(BARCODE_SEGMENT_PATTERN)
      return [1, value.downcase] unless matches

      [0, matches[1].downcase, matches[2].to_i, matches[3].downcase]
    end
  end

  def has_expired?
    expires_at.present? && expires_at <= Current.time
  end

  private

  def normalize_optional_fields
    self.group_name = group_name.presence
    self.description = description.presence
    self.entity_assignment = entity_assignment.presence
    self.order_number = order_number.presence
    self.expires_at = nil if expires_at_before_type_cast.blank?
  end

  # Text the column could not read lands as nil, the same as an empty box, and
  # text it could read may still be a guess; the raw value tells them apart.
  def expires_at_is_readable
    raw = expires_at_before_type_cast
    return if raw.blank? || (expires_at.present? && self.class.readable_expiry?(raw))

    errors.add(:expires_at, EXPIRES_AT_UNREADABLE)
  end
end
