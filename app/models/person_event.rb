# frozen_string_literal: true

# PersonEvent tracks event-year specific data for a person such as agreements signed,
# authorizations, and timesheet confirmation status.
#
# Uses a composite primary key of [person_id, year].
class PersonEvent < ApplicationRecord
  include BasicCacheHelper

  self.table_name = "person_event"
  self.primary_key = [:person_id, :year]

  belongs_to :person

  after_save -> { VehicleEligibility.purge_cache(person_id, year) }

  # Find records based on given query parameters
  # @param query [Hash] optional keys: :person_id, :year
  # @return [Array<PersonEvent>] records sorted by person callsign
  def self.find_for_query(query = {})
    person_id = query[:person_id]
    year = query[:year]

    scope = includes(:person)
    scope = scope.where(person_id: person_id) if person_id.present?
    scope = scope.where(year: year) if year.present?

    scope.sort_by { |pe| pe.person&.callsign.to_s.downcase }
  end

  # Find record for routing - initialize (but don't create) the record if it doesn't exist
  # @param key [String] format: "person_id-year"
  # @return [PersonEvent, nil]
  def self.find_for_route(key)
    person_id, year = key.split("-")
    first_or_new_for_person_year(person_id.to_i, year.to_i)
  end

  # Find or initialize a person event record
  # @param person_id [Integer]
  # @param year [Integer]
  # @return [PersonEvent]
  def self.first_or_new_for_person_year(person_id, year)
    find_or_initialize_by(person_id: person_id, year: year)
  end

  # Find a record for a given person and year
  # @param person_id [Integer]
  # @param year [Integer]
  # @return [PersonEvent, nil]
  def self.find_for_person_year(person_id, year)
    find_by(person_id: person_id, year: year)
  end

  # Check if a column is true for the given person in the current year
  # @param person_id [Integer]
  # @param column [Symbol, String]
  # @return [Boolean]
  def self.is_column_set?(person_id, column)
    where(person_id: person_id, year: Current.year).pick(column) == true
  end

  # Find all records for a given list of person ids and year
  # @param ids [Array<Integer>]
  # @param year [Integer]
  # @return [ActiveRecord::Relation<PersonEvent>]
  def self.find_all_for_ids_year(ids, year)
    where(year: year, person_id: ids)
  end
end
