# frozen_string_literal: true

class PersonCertification < ApplicationRecord
  self.table_name = "person_certification"

  belongs_to :person
  belongs_to :certification
  belongs_to :recorder, class_name: "Person", optional: true

  validates :certification_id, presence: true
  validates :person_id, presence: true

  # Normalize empty strings to nil for date fields
  normalizes :issued_on, :trained_on, with: ->(v) { v.presence }

  scope :with_relationships, -> { includes(:certification, :person, :recorder) }

  class << self
    # Find a certification for a given person
    def find_certification_for_person(certification_id, person_id)
      find_by(certification_id: certification_id, person_id: person_id)
    end

    # Find certifications matching the query criteria
    def find_for_query(query = {})
      sql = with_relationships
      sql = sql.where(person_id: query[:person_id]) if query[:person_id].present?
      sql = sql.where(certification_id: query[:certification_id]) if query[:certification_id].present?
      sql
    end

    def retrieve_all_for_person(person_id)
      Certification.joins(:person_certifications).where(person_certification: { person_id: }).order(:title)
    end
  end
end
