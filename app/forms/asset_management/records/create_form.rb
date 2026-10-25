# frozen_string_literal: true

module AssetManagement
  module Records
    class CreateForm
      include ActiveModel::Model
      include ActiveModel::Attributes

      BARCODE_SEGMENT_PATTERN = /\A(.*?)(\d+)(\D*)\z/
      DEFAULT_GROUP_NAME = "Operations"

      attribute :type, :string
      attribute :barcode, :string
      attribute :description, :string
      attribute :entity_assignment, :string
      attribute :perm_assign, :boolean, default: false
      attribute :group_name, :string
      attribute :expires_on, :date
      attribute :order_number, :string
      attribute :notes, :string
      attribute :copies, :string
      attribute :year, :integer

      validates :barcode, presence: true
      validates :type, presence: true
      validates :year, presence: true, numericality: { only_integer: true }
      validate :copies_must_be_a_positive_integer
      validate :barcode_must_include_a_numeric_segment, if: :multiple_copies_requested?

      attr_reader :created_assets

      def initialize(attributes = {})
        super(default_attributes.merge((attributes || {}).to_h))
        @created_assets = []
      end

      def self.model_name
        ActiveModel::Name.new(self, nil, "Asset")
      end

      def persisted?
        false
      end

      def save
        return false unless valid?

        @created_assets = []

        Asset.transaction do
          generated_barcodes.each do |generated_barcode|
            asset = Asset.new(asset_attributes.merge(barcode: generated_barcode))
            asset.save!
            @created_assets << asset
          end
        end

        true
      rescue ActiveRecord::RecordInvalid => e
        merge_asset_errors(e.record)
        @created_assets = []
        false
      end

      def created_count
        @created_assets.length
      end

      private

      def default_attributes
        {
          type: Asset::TYPE_RADIO,
          group_name: DEFAULT_GROUP_NAME,
          perm_assign: false,
          year: Current.year
        }
      end

      def cleaned_barcode
        barcode.to_s.strip
      end

      def copy_count
        copies.present? ? copies.to_i : 1
      end

      def multiple_copies_requested?
        copy_count > 1
      end

      def generated_barcodes
        return [cleaned_barcode] unless multiple_copies_requested?

        prefix, base_number, suffix, numeric_length = barcode_parts

        copy_count.times.map do |offset|
          "#{prefix}#{"%0#{numeric_length}d" % (base_number + offset)}#{suffix}"
        end
      end

      def barcode_parts
        matches = cleaned_barcode.match(BARCODE_SEGMENT_PATTERN)
        [
          matches[1],
          matches[2].to_i,
          matches[3],
          matches[2].length
        ]
      end

      def asset_attributes
        {
          type:,
          description:,
          entity_assignment:,
          perm_assign:,
          group_name:,
          expires_on:,
          order_number:,
          notes:,
          year:
        }
      end

      def copies_must_be_a_positive_integer
        return if copies.blank?
        return if copies.match?(/\A\d+\z/) && copies.to_i.positive?

        errors.add(:copies, "Copies must be a positive whole number.")
      end

      def barcode_must_include_a_numeric_segment
        return if cleaned_barcode.match?(BARCODE_SEGMENT_PATTERN)

        errors.add(:barcode, "The barcode must include a number when creating multiple copies.")
      end

      def merge_asset_errors(record)
        record.errors.each do |error|
          errors.add(error.attribute, error.message)
        end
      end
    end
  end
end
