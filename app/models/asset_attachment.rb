# frozen_string_literal: true

class AssetAttachment < ApplicationRecord
  self.table_name = "asset_attachment"
  self.audit_model = true

  RADIO = "Radio"
  VEHICLE = "Vehicle"
  PARENT_TYPE_RADIO = RADIO
  PARENT_TYPE_VEHICLE = VEHICLE
  PARENT_TYPES = [RADIO, VEHICLE].freeze

  validates :parent_type, presence: true, inclusion: { in: PARENT_TYPES }
  validates :description, presence: true, length: { maximum: 32 }

  class << self
    def find_all
      order(:description)
    end

    alias_method :findAll, :find_all
  end
end
