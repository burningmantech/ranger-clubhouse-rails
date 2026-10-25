class SurveyGroup < ApplicationRecord
  include SortIndexLine

  self.table_name = "survey_group"
  self.inheritance_column = nil # Disable STI
  self.audit_model = true

  # Constants
  TYPE_NORMAL = "normal"
  TYPE_TRAINER = "trainer"
  TYPE_SEPARATE = "separate-slot"
  TYPE_SUMMARY = "separate-summary"

  # Every kind of group, in the order the survey form offers them.
  TYPES = [TYPE_NORMAL, TYPE_TRAINER, TYPE_SEPARATE, TYPE_SUMMARY].freeze

  # The two kinds that stand as a report of their own, and so need a name for
  # it -- the reports page lists them by that name.
  SEPARATE_TYPES = [TYPE_SEPARATE, TYPE_SUMMARY].freeze

  # Relations
  belongs_to :survey
  has_many :survey_questions, -> { ordered }, dependent: :destroy
  # Answers are plain rows with nothing hanging off them, and a group holds
  # one per question per person, so they go in a single statement.
  has_many :survey_answers, dependent: :delete_all

  # Validations
  validates :survey_id, presence: true, numericality: { only_integer: true }
  validates :sort_index, presence: true, numericality: { only_integer: true }
  validates :title, presence: { message: "Group title can't be blank" },
            length: { maximum: 190, message: "Group title is too long (190 characters at most)" }
  validates :type, presence: true,
            inclusion: { in: TYPES, allow_blank: true,
                         message: "Group type must be one of the kinds this page offers" }
  validates :description, allow_blank: true, length: { maximum: 65535 }
  # The column holds 191 characters, so a longer one has to be refused here:
  # MySQL raises rather than answering the form. Capped at 190 to match every
  # other title in this family.
  validates :report_title, allow_blank: true,
            length: { maximum: 190, message: "Report title is too long (190 characters at most)" }
  validates :report_title,
            presence: { message: "Report title is needed for a group that has a report of its own" },
            if: :separate_report?

  # Attributes defaults. The text columns hold no nulls, so a group saved
  # without a description stores an empty string rather than failing.
  attribute :sort_index, :integer, default: 1
  attribute :report_title, :string, default: ""
  attribute :description, :string, default: ""

  validate :type_settled_once_answered

  # Scopes
  scope :for_survey, ->(survey_id) { where(survey_id: survey_id).ordered }

  def self.find_all_for_survey(survey_id)
    for_survey(survey_id)
  end

  # A group's kind decides how its answers are read: answers given under a
  # standard group carry no trainer, so filing them under a per-trainer group
  # hides every one of them from the report. The wording can still be fixed.
  def type_settled_once_answered
    return unless persisted? && type_changed?
    return unless survey_answers.exists?

    errors.add(:type, "Group type cannot be changed once people have answered its questions.")
  end

  # Is this group reported on its own, rather than as part of the survey's
  # main report?
  def separate_report?
    SEPARATE_TYPES.include?(type)
  end

  def get_report_id
    if type == TYPE_NORMAL
      "main"
    else
      id
    end
  end

  def get_report_title_default(survey_type)
    case type
    when TYPE_NORMAL
      ""
    when TYPE_TRAINER
      if survey_type == Survey::ALPHA
        "Alpha Feedback For Mentors"
      else
        Survey::TYPE_FOR_REPORTS_LABELS[survey_type] || type
      end
    else
      report_title
    end
  end

  private

  # The groups of the same survey, which is the line this one is ordered in.
  def line_scope
    self.class.where(survey_id:)
  end
end
