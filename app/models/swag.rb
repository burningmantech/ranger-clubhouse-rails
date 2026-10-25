# frozen_string_literal: true

require "naturally"

class Swag < ApplicationRecord
  self.table_name = "swag"
  self.inheritance_column = nil # allow swag.type to be used

  # Constants for swag types
  TYPE_DEPT_PATCH = "dept-patch"
  TYPE_DEPT_PIN = "dept-pin"
  TYPE_DEPT_SHIRT = "dept-shirt"
  TYPE_ORG_PATCH = "org-patch"
  TYPE_ORG_PIN = "org-pin"
  TYPE_OTHER = "other"

  # Constants for shirt types
  SHIRT_T_SHIRT = "t-shirt"
  SHIRT_LONG_SLEEVE = "long-sleeve"

  # Shirt size sort weights for ordering
  SHIRT_SORT_WEIGHTS = {
    "xs" => 1,
    "s" => 2,
    "m" => 3,
    "l" => 4,
    "xl" => 5,
    "xxl" => 6,
    "2xl" => 6,
    "3xl" => 7,
    "4xl" => 8,
    "5xl" => 9
  }.freeze

  # Shirt type sort weights
  SHIRT_TYPE_SORT_WEIGHT = {
    SHIRT_T_SHIRT => 1,
    SHIRT_LONG_SLEEVE => 2
  }.freeze

  # Valid types for validation
  VALID_TYPES = [
    TYPE_DEPT_PATCH,
    TYPE_DEPT_PIN,
    TYPE_DEPT_SHIRT,
    TYPE_ORG_PATCH,
    TYPE_ORG_PIN,
    TYPE_OTHER
  ].freeze

  VALID_SHIRT_TYPES = [
    SHIRT_T_SHIRT,
    SHIRT_LONG_SLEEVE
  ].freeze

  # Associations
  has_many :person_swag, dependent: :destroy, foreign_key: "swag_id"

  # Validations
  validates :active, inclusion: [true, false]
  validates :title, presence: true
  validates :type, presence: true, inclusion: VALID_TYPES
  validates :shirt_type, inclusion: { in: VALID_SHIRT_TYPES, allow_blank: true }
  validates :description, length: { maximum: 65535 }, allow_blank: true

  # Callbacks
  before_destroy :cleanup_person_shirt_references

  # Scopes for common queries
  scope :active, -> { where(active: true) }
  scope :inactive, -> { where(active: false) }
  scope :by_type, ->(type) { where(type: type) }
  scope :dept_shirts, -> { where(type: TYPE_DEPT_SHIRT) }
  scope :sorted, -> { order(:title) }

  # Normalize shirt_type to blank string instead of nil
  def shirt_type
    super.presence || ""
  end

  # Normalize description to blank string instead of nil
  def description
    super.presence || ""
  end

  # Class method: Find swag based on query parameters
  # @param query [Hash] Query parameters (type, active)
  # @return [Array<Swag>] Sorted array of swag items
  def self.find_for_query(query = {})
    relation = all

    relation = relation.by_type(query[:type]) if query[:type].present?
    relation = relation.where(active: query[:active]) if query.key?(:active)

    sort_swag(relation.load)
  end

  # Retrieve all department shirts
  def self.retrieve_shirts
    find_for_query(type: TYPE_DEPT_SHIRT)
  end

  # Sort swag items by type and title
  # For shirts, uses intelligent sorting based on shirt type and size
  def self.sort_swag(rows)
    sorted = []
    grouped = rows.group_by(&:type)

    grouped.each do |type, group|
      sorted_group = if type != TYPE_DEPT_SHIRT
        Naturally.sort_by(group) { |e| e.title.downcase }
                     else
        group.sort do |a, b|
          a_title = a.title
          b_title = b.title

          # For shirts, sort by shirt type first
          a_type_weight = a.shirt_type.blank? ? 3 : (SHIRT_TYPE_SORT_WEIGHT[a.shirt_type] || 99)
          b_type_weight = b.shirt_type.blank? ? 3 : (SHIRT_TYPE_SORT_WEIGHT[b.shirt_type] || 99)

          if a_type_weight != b_type_weight
            a_type_weight <=> b_type_weight
          else
            # Then sort by title and size
            a_processed_title, a_weight = shirt_sort_weight(a_title)
            b_processed_title, b_weight = shirt_sort_weight(b_title)

            title_comparison = a_processed_title.downcase <=> b_processed_title.downcase

            if title_comparison != 0
              title_comparison
            else
              a_weight <=> b_weight
            end
          end
        end
                     end

      sorted.concat(sorted_group)
    end

    sorted
  end

  # Class method: Extract sort weight from shirt title
  # Extracts size information from title and returns sort weight
  # @param title [String] Shirt title
  # @return [Array] [processed_title, weight]
  def self.shirt_sort_weight(title)
    # Match pattern: text + size + optional chest measurement
    # Examples: "T-Shirt XL", "T-Shirt 2XL 37"", "Long Sleeve M"
    match = title.match(/^(.+)\s+(\d?-?[lmsx]+)(\s+\d+(\s*-\d+\s*)?\")?$/i)

    return [title, 99] if match.nil? || match.length < 3

    processed_title = match[1]
    size = match[2].downcase.delete("-")
    weight = SHIRT_SORT_WEIGHTS[size] || 99

    [processed_title, weight]
  end

  private

  # Callback: Delete associated PersonSwag records before destroying
  def cleanup_person_swag_references
    person_swags.destroy_all
  end

  # Callback: Nullify person shirt references if this is a department shirt
  def cleanup_person_shirt_references
    return unless type == TYPE_DEPT_SHIRT

    # Nullify all shirt references in the person table
    Person.where(tshirt_swag_id: id).update_all(tshirt_swag_id: nil)
    Person.where(tshirt_secondary_swag_id: id).update_all(tshirt_secondary_swag_id: nil)
    Person.where(long_sleeve_swag_id: id).update_all(long_sleeve_swag_id: nil)
  end
end
