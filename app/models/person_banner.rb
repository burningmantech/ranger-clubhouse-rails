# frozen_string_literal: true

class PersonBanner < ApplicationRecord
  self.table_name = "person_banner"

  belongs_to :person
  belongs_to :creator_person, class_name: "Person", optional: true
  belongs_to :updater_person, class_name: "Person", optional: true

  validates :person_id, presence: true
  validates :message, presence: true

  normalizes :message, apply_to_nil: true, with: ->(v) { v.to_s }

  before_create :set_creator
  before_update :set_updater

  # Find banners based on given query parameters.
  # @param query [Hash] optional keys: :person_id, :year, :is_permanent, :active, :include_person
  # @return [Array<PersonBanner>]
  def self.find_for_query(query = {})
    person_id = query[:person_id]
    year = query[:year]
    active = query[:active]
    include_person = query[:include_person]

    scope = includes(:person)
    scope = scope.where(person_id:) if person_id.present?
    scope = scope.where_year("created_at", year) if year.present?
    scope = scope.where(is_permanent: query[:is_permanent]) if query.key?(:is_permanent)
    scope = scope.where("is_permanent = TRUE OR YEAR(created_at) = ?", Current.year) if active
    scope = scope.includes(:creator_person, :updater_person) if include_person

    scope.order(:created_at)
         .load
         .sort_by { |r| [r.person.callsign.to_s.downcase, r.created_at.year] }
  end

  private

  def set_creator
    self.creator_person_id ||= Current.person_id
    self.created_at ||= Current.time
  end

  def set_updater
    self.updater_person_id = Current.person_id
  end
end
