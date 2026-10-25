# frozen_string_literal: true

class Asset < ApplicationRecord
  self.table_name = "asset"
  self.audit_model = true
  self.inheritance_column = :none

  BLANK_FILTER_VALUE = "Blank"
  BARCODE_SEGMENT_PATTERN = /\A(.*?)(\d+)(\D*)\z/

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
  validates :description, length: { maximum: 25 }, allow_nil: true
  validates :type, presence: true
  validates :year, presence: true, numericality: { only_integer: true }

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

      expires_on = arel_table[:expires_on]

      case value.to_s
      when "expired"
        scope.where(expires_on.lteq(Current.today))
      when "not-expired"
        scope.where(expires_on.eq(nil).or(expires_on.gt(Current.today)))
      else
        scope.where(expires_on: Date.iso8601(value.to_s))
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
    expires_on.present? && expires_on <= Current.today
  end

  private

  def normalize_optional_fields
    self.group_name = group_name.presence
    self.description = description.presence
    self.entity_assignment = entity_assignment.presence
    self.order_number = order_number.presence
    self.expires_on = nil if expires_on_before_type_cast.blank?
  end
end
