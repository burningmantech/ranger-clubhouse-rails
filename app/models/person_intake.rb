# frozen_string_literal: true

class PersonIntake < ApplicationRecord
  self.table_name = "person_intake"

  belongs_to :person

  def self.find_for_person_year_or_new(person_id, year)
    find_by(person_id: person_id, year: year) || new(person_id: person_id, year: year)
  end

  # People among the ids carrying a personnel flag for the year (upstream
  # PersonIntake::retrievePersonnelIssueForIdsYear).
  # @param person_ids [Array<Integer>]
  # @param year [Integer]
  # @return [Array<Integer>] flagged person ids
  def self.personnel_issue_for_ids_year(person_ids, year)
    return [] if person_ids.blank?

    where(person_id: person_ids, year: year, personnel_rank: Intake::FLAG).pluck(:person_id)
  end

  def personnel_rank
    rank_or_nil(super)
  end

  def mentor_rank
    rank_or_nil(super)
  end

  def rrn_rank
    rank_or_nil(super)
  end

  def vc_rank
    rank_or_nil(super)
  end

  private

  # Port of the PHP NullIfEmptyAttribute cast: a blank or zero rank reads as
  # "no rank set" rather than as an actual rank value.
  def rank_or_nil(value)
    value.nil? || value.zero? ? nil : value
  end
end
