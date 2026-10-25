class PersonOnlineCourse < ApplicationRecord
  self.table_name = "person_online_course"
  self.inheritance_column = nil # Disable STI as 'type' is used for course type

  # Constants
  TYPE_MOODLE = "moodle"
  TYPE_MANUAL_REVIEW = "manual-review" # prior to 2020

  # Attributes
  attribute :type, :string, default: TYPE_MOODLE

  # Relationships
  belongs_to :person
  belongs_to :online_course
  belongs_to :position, optional: true

  # Validations
  validates :type, presence: true

  scope :for_year, ->(year) { where_year("completed_at", year) }

  class << self
    # Find the online course completion records based on the given query.
    #
    # @param query [Hash]
    # @return [ActiveRecord::Relation]
    def find_for_query(query)
      scope = includes(:person).joins(:person)

      scope = scope.for_year(query[:year]) if query[:year].present?
      scope = scope.where(person_id: query[:person_id]) if query[:person_id].present?
      scope = scope.where(type: query[:type]) if query[:type].present?
      scope = scope.where(online_course_id: query[:online_course_id]) if query[:online_course_id].present?
      scope = scope.where(position_id: query[:position_id]) if query[:position_id].present?

      scope.order("person.callsign")
    end

    # Find a person's online course for given year and position
    #
    # @param person_id [Integer]
    # @param year [Integer]
    # @param position_id [Integer]
    # @return [PersonOnlineCourse, nil]
    def find_for_person_year(person_id, year, position_id)
      where(year:, person_id:, position_id:).first
    end

    # Did the given person complete the online course in a specific year?
    #
    # @param person_id [Integer]
    # @param year [Integer]
    # @param position_id [Integer]
    # @return [Boolean]
    def did_complete_for_year?(person_id, year, position_id)
      where(person_id: person_id, year: year, position_id: position_id)
        .where.not(completed_at: nil)
        .exists?
    end

    # Did the given person complete a specific course?
    #
    # @param person_id [Integer]
    # @param course [OnlineCourse]
    # @return [Boolean]
    def did_complete_course?(person_id, course)
      where(person_id: person_id, online_course_id: course.id, year: course.year)
        .where.not(completed_at: nil)
        .exists?
    end

    # Find or initialize for person, year, and position
    #
    # @param person_id [Integer]
    # @param year [Integer]
    # @param position_id [Integer]
    # @return [PersonOnlineCourse]
    def first_or_new_for_person_year(person_id, year, position_id)
      find_or_initialize_by(
        person_id: person_id,
        year: year,
        position_id: position_id
      )
    end
  end
end
