# frozen_string_literal: true

class PersonAward < ApplicationRecord
  self.table_name = "person_award"

  belongs_to :person
  # An award recognizes exactly one of a team, a position or a special award, so the other
  # two columns are null -- as is creator_person_id for automatically granted awards. The
  # "at least one of the three" rule lives in #validate_award_requirements.
  belongs_to :award, optional: true
  belongs_to :team, optional: true
  belongs_to :position, optional: true
  belongs_to :creator_person, class_name: "Person", foreign_key: :creator_person_id, optional: true

  # Optional above only means the column may be null. A column which does name a row must
  # name one that exists -- there is no foreign key constraint behind these to catch it.
  # creator_person_id gets no such check on purpose: it is never form input (the controller
  # sets it from Current.person_id), and deleting the granting admin's account would
  # otherwise leave the award permanently unsaveable over a field no form can clear.
  validates :award, presence: true, if: -> { award_id.present? }
  validates :team, presence: true, if: -> { team_id.present? }
  validates :position, presence: true, if: -> { position_id.present? }

  validate :validate_award_requirements

  after_save -> { YearsManagement.update_years_of_awards(person_id) }
  after_destroy -> { YearsManagement.update_years_of_awards(person_id) }

  # The earliest an award is allowed to be given.
  FIRST_YEAR_PERMITTED = 1996

  validates :year, numericality: { greater_than_or_equal_to: FIRST_YEAR_PERMITTED }

  MISSING_TYPE_ERROR = "either award_id, position_id, team_id must be specified"

  def self.find_for_query(query = {})
    sql = includes(:award, :team, :position, :person)
    sql = sql.where(person_id: query[:person_id]) if query[:person_id].present?
    sql = sql.where(award_id: query[:award_id]) if query[:award_id].present?
    sql = sql.where(position_id: query[:position_id]) if query[:position_id].present?
    sql = sql.where(team_id: query[:team_id]) if query[:team_id].present?
    sql.load.sort_by { |r| [r.title.downcase, r.year] }
  end

  # Retrieve all awards given to a person. Classify into team and special service awards.
  def self.retrieve_for_person(person_id)
    rows = find_for_query(person_id: person_id)

    groups = rows.each_with_object({ teams: {}, positions: {}, special: {} }) do |row, hash|
      category, id, title = award_category_info(row)

      hash[category][id] ||= {
        id: id,
        title: title,
        years: [],
        service_years: []
      }

      hash[category][id][:years] << row.year
      hash[category][id][:service_years] << row.year if row.awards_grants_service_year
    end

    {
      teams: sort_award_group(groups[:teams]),
      positions: sort_award_group(groups[:positions]),
      special: sort_award_group(groups[:special])
    }
  end

  def title
    if team_id
      team&.title
    else
      if award_id
        award&.title
      else
        position&.title
      end
    end
  end

  private

  def validate_award_requirements
    # Check if at least one type is present
    if award_id.blank? && position_id.blank? && team_id.blank?
      errors.add(:award_id, MISSING_TYPE_ERROR)
      errors.add(:position_id, MISSING_TYPE_ERROR)
      errors.add(:team_id, MISSING_TYPE_ERROR)
      return false
    end

    if award_id_changed? || position_id_changed? || team_id_changed? || year_changed?
      column = nil
      value = nil

      if award_id.present?
        column = :award_id
        value = award_id
      elsif position_id.present?
        column = :position_id
        value = position_id
      elsif team_id.present?
        column = :team_id
        value = team_id
      end

      # if no associated entity has been set, the default validation rules will fail.
      if column && person_id.present? && year.present?
        query = self.class.where(column => value)
                    .where(person_id: person_id)
                    .where(year: year)

        query = query.where.not(id: id) if persisted?

        if query.exists?
          errors.add(column, "award already exists for the year")
          return false
        end
      end
    end

    # Check awards eligibility
    if team_id.present? && team && !team.awards_eligible
      errors.add(:team_id, "Team is not eligible for awards")
      return false
    elsif position_id.present? && position && !position.awards_eligible
      errors.add(:position_id, "Position is not eligible for awards")
      return false
    end

    true
  end

  # Determine award category, id, and title for a given row
  def self.award_category_info(row)
    if row.team_id
      [:teams, row.team_id, row.team&.title || "Unknown award [#{row.team_id}]"]
    elsif row.position_id
      [:positions, row.position_id, row.position&.title || "Unknown award [#{row.position_id}]"]
    else
      [:special, row.award_id, row.award&.title || "Unknown award [#{row.award_id}]"]
    end
  end

  # Sort award group by title, then sort years within each award
  def self.sort_award_group(awards_hash)
    awards_hash.values
               .sort_by { |award| award[:title].downcase }
               .each do |award|
      award[:years].sort!
      award[:service_years].sort!
    end
  end
end
