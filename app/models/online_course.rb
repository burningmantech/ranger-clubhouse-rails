# frozen_string_literal: true

class OnlineCourse < ApplicationRecord
  self.table_name = "online_course"

  # Which course a position uses decides who gets enrolled, so every change
  # is recorded.
  self.audit_model = true

  # Audience the course is intended for (the course_for enum column).
  COURSE_FOR_ALL = "all"
  COURSE_FOR_RETURNING = "returning"
  COURSE_FOR_NEW = "new"

  # Relationships
  belongs_to :position

  # Scopes
  scope :active, -> { where(active: true) }
  scope :for_year, ->(year) { where(year:) }

  # Validations
  validates :course_id, presence: true
  validates :course_for, inclusion: { in: [COURSE_FOR_ALL, COURSE_FOR_RETURNING, COURSE_FOR_NEW] }
  validates :year, numericality: { only_integer: true, greater_than_or_equal_to: 2000 }
  validates :position_id, uniqueness: { scope: [:year, :course_for],
                                         message: "This position already has a course for this year and audience." }

  class << self
    # Active online courses for a position and year, ordered for a <select>.
    #
    # @param position_id [Integer]
    # @param year [Integer]
    # @return [ActiveRecord::Relation]
    def active_for_position_year(position_id, year)
      active.where(position_id:, year:).order(:name)
    end
  end
end
