class SurveyQuestion < ApplicationRecord
  include SortIndexLine

  self.table_name = "survey_question"
  self.inheritance_column = nil # Disable STI
  self.audit_model = true

  # Constants
  TYPE_RATING = "rating"
  TYPE_OPTIONS = "options"
  TYPE_TEXT = "text"

  # Every kind of question, in the order the question form offers them.
  TYPES = [TYPE_RATING, TYPE_TEXT, TYPE_OPTIONS].freeze

  # Relations
  belongs_to :survey
  belongs_to :survey_group
  # Answers are plain rows with nothing hanging off them, and a question asked
  # of a whole class holds thousands, so they go in a single statement.
  has_many :survey_answers, dependent: :delete_all

  # Validations
  validates :type, presence: true,
            inclusion: { in: TYPES, allow_blank: true,
                         message: "Question type must be one of the kinds this page offers" }
  validates :survey_id, presence: true
  validates :survey_group_id, presence: true
  validates :sort_index, presence: true, numericality: { only_integer: true }
  validates :description, presence: { message: "Question can't be blank" },
            length: { maximum: 65535, message: "Question is too long" }
  validates :options,
            presence: { message: "Choices are needed for a question answered from a list" },
            if: -> { type == TYPE_OPTIONS }
  validates :options, allow_blank: true,
            length: { maximum: 65535, message: "There are too many choices to store" }

  # Attributes
  attribute :is_required, :boolean, default: false
  attribute :summarize_rating, :boolean, default: false
  attribute :options, :string, default: ""

  # A question carries only the settings its own kind uses. Choices left on a
  # rating question would be read as the labels for its ratings, and the page
  # would offer to summarize a question that has nothing to summarize.
  before_validation :clear_settings_of_other_types

  validate :type_settled_once_answered

  # Ordered the way every page orders them. The id breaks both ties: rows on
  # file repeat sort_index, and Ruby's sort_by is not stable, so without it the
  # reports could list two questions in one order and the other pages in
  # another.
  def self.find_all_for_survey(survey_id)
    where(survey_id: survey_id)
      .includes(:survey_group)
      .sort_by { |q| [q.survey_group.sort_index, q.survey_group_id, q.sort_index, q.id] }
  end

  def self.find_all_for_survey_group(survey_group_id)
    where(survey_group_id: survey_group_id).ordered
  end

  # The choices offered for this question, one per line as they were typed.
  def option_list
    options.to_s.lines.map(&:strip).reject(&:empty?)
  end

  # An answer means something different under each kind: a written answer read
  # as a rating counts as nothing, and the choices it was picked from are
  # cleared in the same save. The wording can still be corrected.
  def type_settled_once_answered
    return unless persisted? && type_changed?
    return unless survey_answers.exists?

    errors.add(:type, "Question type cannot be changed once people have answered it. " \
                      "Delete this question and add a new one instead.")
  end

  private

  def clear_settings_of_other_types
    self.options = (type == TYPE_OPTIONS) ? option_list.join("\n") : ""
    self.summarize_rating = false unless type == TYPE_RATING
  end

  # The questions of the same group, which is the line this one is ordered in.
  def line_scope
    self.class.where(survey_group_id:)
  end
end
