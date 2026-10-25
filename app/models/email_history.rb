# frozen_string_literal: true

class EmailHistory < ApplicationRecord
  self.table_name = "email_history"

  belongs_to :person
  belongs_to :source_person,
             -> { select(:id, :callsign, :status) },
             class_name: "Person",
             foreign_key: :source_person_id,
             optional: true

  def self.find_for_query(query)
    q = query.to_h.symbolize_keys

    scope = self
    scope = scope.where(person_id: q[:person_id]) if q[:person_id]
    scope = scope.where(source_person_id: q[:source_person_id]) if q[:source_person_id]
    scope = scope.includes(:source_person) if q[:include_source_person]
    scope = scope.where(email: q[:email]) if q[:email]
    scope.order(:created_at)
  end

  # Create a new history record
  def self.record(person_id, email, source_person_id = nil)
    create(
      person_id: person_id,
      email: email,
      source_person_id: source_person_id
    )
  end
end
