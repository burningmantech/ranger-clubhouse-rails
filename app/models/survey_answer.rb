class SurveyAnswer < ApplicationRecord
  self.table_name = "survey_answer"

  RATING_OPTIONS = [
    { id: 1, title: "1 - Terrible!" },
    { id: 2, title: "2" },
    { id: 3, title: "3" },
    { id: 4, title: "4 - Ok / Neutral" },
    { id: 5, title: "5" },
    { id: 6, title: "6" },
    { id: 7, title: "7 - Fantastic!" }
  ].freeze

  # Relations
  belongs_to :person
  belongs_to :trainer, class_name: "Person", optional: true
  belongs_to :survey
  belongs_to :survey_group
  belongs_to :survey_question
  belongs_to :slot, optional: true

  # Validations
  validates :person_id, presence: true
  validates :survey_group_id, presence: true
  validates :survey_id, presence: true
  validates :survey_question_id, presence: true
  validate :validate_response_requirement

  # Attributes defaults
  attribute :can_share_name, :boolean, default: false

  def validate_response_requirement
    if survey_question&.is_required && response.blank?
      errors.add(:response, "A response is required.")
    end
  end

  # Class Methods
  def self.delete_all_for_person_slot(survey_id, person_id, slot_id)
    where(survey_id: survey_id, person_id: person_id, slot_id: slot_id).delete_all
  end

  def self.need_alpha_survey_response?(person_id, year)
    survey_id = Survey.where(year: year, type: Survey::ALPHA).pick(:id)
    return false unless survey_id

    !exists?(survey_id: survey_id, person_id: person_id)
  end

  def self.delete_all_for_survey(survey_id, person_id)
    where(survey_id: survey_id, person_id: person_id).delete_all
  end

  def self.delete_for_slot(slot_id)
    where(slot_id: slot_id).delete_all
  end

  def self.have_trainer_feedback?(person_id)
    exists?(trainer_id: person_id)
  end
end
