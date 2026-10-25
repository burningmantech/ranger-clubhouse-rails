# app/models/person_swag.rb

class PersonSwag < ApplicationRecord
  self.table_name = "person_swag"

  # Associations
  belongs_to :person
  belongs_to :swag

  # Validations
  validates :person_id, presence: true
  validates :swag_id, presence: true
  validates :person_id, uniqueness: { scope: :swag_id, message: "This person already has this swag." }
  validates :year_issued, numericality: { only_integer: true, allow_nil: true }
  validates :notes, length: { maximum: 2000 }, allow_blank: true

  # Scopes for common queries
  scope :with_swag, -> { includes(:swag) }
  scope :with_person, -> { includes(:person) }
  # Note: Rails doesn't support partial select on includes like Laravel
  # Use includes(:person) and access person.callsign, person.status directly

  # Normalize notes to blank string instead of nil
  def notes
    super.presence || ""
  end

  # Setter for notes - convert empty to blank string
  def notes=(value)
    super(value.presence || "")
  end

  # Class method: Find swag assignments based on query parameters
  # @param query [Hash] Query parameters (person_id, swag_id, year_issued, include_person)
  # @return [Array<PersonSwag>] Sorted array of person_swag records
  def self.find_for_query(query = {})
    person_id = query[:person_id]
    swag_id = query[:swag_id]
    year_issued = query[:year_issued]
    include_person = query[:include_person]

    # Start with base relation that includes swag
    scope = with_swag
    scope = scope.where(person_id:) if person_id
    scope = scope.where(swag_id:) if swag_id
    scope = scope.where(year_issued:) if year_issued

    # Include person details if requested
    scope = scope.includes(:person) if include_person

    # Execute query and sort by swag title (natural sort)
    scope.sort_by { |record| record.swag&.title.to_s.downcase }
  end
end
