# frozen_string_literal: true

# Form object for survey responses, providing ActiveModel compatibility
# so AppFormBuilder can handle labels, error display, and field values automatically.
#
# Dynamically defines fields based on the survey structure (questions + trainers),
# since surveys have variable questions loaded from the database.
#
# @example Controller usage
#   @survey_response = SurveyResponseForm.new(survey: @survey, trainers: @trainers)
#   @survey_response.assign_errors(errors_hash) # on validation failure
#
class SurveyResponseForm
  include ActiveModel::Model

  attr_reader :fields

  # Initialize with the survey structure and optional submitted values
  #
  # @param survey [Survey] The survey being responded to
  # @param trainers [Array<Person>] Trainers being evaluated (if any)
  # @param values [Hash] Submitted form values (from params[:survey])
  #
  def initialize(survey:, trainers: [], values: {})
    @fields = {}
    build_field_list(survey, trainers)
    values.each { |key, value| @fields[key.to_s] = value if @fields.key?(key.to_s) }
  end

  # Dynamic attribute access for form builder compatibility.
  # The form builder calls object.send(:attribute_name) to retrieve field values.
  #
  def method_missing(method, *args)
    key = method.to_s.chomp("=")
    return super unless @fields.key?(key)

    if method.to_s.end_with?("=")
      @fields[key] = args.first
    else
      @fields[key]
    end
  end

  def respond_to_missing?(method, include_private = false)
    @fields.key?(method.to_s.chomp("=")) || super
  end

  # Populate ActiveModel errors from the controller's validation hash.
  # This enables the form builder's automatic error styling and messages.
  #
  # @param errors_hash [Hash<String, String>] Field name => error message pairs
  #
  def assign_errors(errors_hash)
    errors_hash.each { |field, message| errors.add(field.to_sym, message) }
  end

  private

  def build_field_list(survey, trainers)
    is_trainer_survey = (survey.type == Survey::TRAINER)

    survey.survey_groups.each do |group|
      if is_trainer_survey
        # For trainer surveys, each trainer gets all questions + share_name toggle
        trainers.each do |trainer|
          @fields["share_name_#{trainer.id}"] = "1"

          group.survey_questions.each do |question|
            @fields["question_#{question.id}_#{trainer.id}"] = ""
          end
        end
      elsif group.type == SurveyGroup::TYPE_TRAINER
        # For student surveys with trainer-specific groups
        trainers.each do |trainer|
          group.survey_questions.each do |question|
            @fields["question_#{question.id}_#{trainer.id}"] = ""
          end
        end
      else
        # For normal (non-trainer) groups
        group.survey_questions.each do |question|
          @fields["question_#{question.id}"] = ""
        end
      end
    end
  end
end
