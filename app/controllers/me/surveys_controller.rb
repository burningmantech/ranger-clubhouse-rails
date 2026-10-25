# frozen_string_literal: true

class Me::SurveysController < ApplicationController
  layout "me"

  before_action :load_survey_params, only: [:show, :create]
  before_action :load_survey_data, only: [:show]

  def show
    @survey_response = SurveyResponseForm.new(survey: @survey, trainers: @trainers)
    @trainer_name = determine_trainer_name
  end

  def create
    survey_sheet = load_survey_for_submission
    @survey = survey_sheet.survey
    @slot = survey_sheet.slot
    @trainers = survey_sheet.targets

    # Validate required responses BEFORE any DB operations
    errors = validate_survey_responses
    if errors.any?
      @survey_response = SurveyResponseForm.new(survey: @survey, trainers: @trainers, values: params[:survey])
      @survey_response.assign_errors(errors)
      @trainer_name = determine_trainer_name
      flash.now[:error] = "Please answer all required questions before submitting."
      render :show, status: :unprocessable_entity
      return
    end

    # Read before the old answers are deleted: expect refuses a survey scope
    # that is not a set of answers, so a malformed request cannot clear them.
    answers = params.expect(survey: {})

    # Delete existing answers for this person/survey/slot
    if @type == Survey::ALPHA
      SurveyAnswer.delete_all_for_survey(@survey.id, current_user.id)
    else
      SurveyAnswer.delete_all_for_person_slot(@survey.id, current_user.id, @slot&.id)
    end

    is_trainer_survey = (@survey.type == Survey::TRAINER)

    # Process survey answers in a transaction
    ActiveRecord::Base.transaction do
      process_survey_answers(@survey, is_trainer_survey, @slot&.id, answers)
    end

    redirect_to me_root_path, success: "Survey responses saved."
  rescue ArgumentError => e
    redirect_to me_root_path, error: e.message
  rescue ActiveRecord::RecordNotFound
    redirect_to me_root_path, error: "Survey not found."
  rescue => e
    Rails.logger.error("Survey submission error: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    redirect_to me_root_path, error: "An error occurred while saving your responses. Please try again."
  end

  private

  def load_survey_params
    @type = params.fetch(:type)
    @slot_id = params[:slot_id]&.to_i
    @year = params[:year]&.to_i || Current.year

    unless Survey::TYPE_FOR_REPORTS_LABELS.key?(@type)
      redirect_to me_root_path, error: "Invalid survey type."
      return false
    end

    if @type != Survey::ALPHA && @slot_id.nil?
      redirect_to me_root_path, error: "Slot ID is required for this survey type."
      return false
    end

    if @type == Survey::ALPHA && @year.nil?
      redirect_to me_root_path, error: "Year is required for Alpha surveys."
      return false
    end

    true
  rescue KeyError
    redirect_to me_root_path, error: "Survey type is required."
    false
  end

  def load_survey_data
    survey_info = case @type
                  when Survey::ALPHA
                    SurveyBuilder.retrieve_alpha_survey(@year, current_user)
                  when Survey::MENTOR_FOR_MENTEES, Survey::MENTEES_FOR_MENTOR
                    SurveyBuilder.retrieve_mentoring_survey(@type, @slot_id, current_user)
                  else
                    SurveyBuilder.retrieve_slot_survey_trainers(@type, @slot_id, current_user)
                  end

    @survey = survey_info.survey
    @trainers = survey_info.targets
    @slot = survey_info.slot
    true
  rescue ArgumentError => e
    redirect_to me_root_path, error: e.message
  rescue ActiveRecord::RecordNotFound
    redirect_to me_root_path, error: "Survey not found."
  end

  def load_survey_for_submission
    case @type
    when Survey::ALPHA
      SurveyBuilder.retrieve_alpha_survey(@year, current_user)
    when Survey::MENTOR_FOR_MENTEES, Survey::MENTEES_FOR_MENTOR
      SurveyBuilder.retrieve_mentoring_survey(@type, @slot_id, current_user)
    else
      SurveyBuilder.retrieve_slot_survey_trainers(@type, @slot_id, current_user)
    end
  end

  def determine_trainer_name
    case @type
    when Survey::ALPHA
      "Mentor"
    when Survey::MENTOR_FOR_MENTEES
      "Mentee"
    when Survey::MENTEES_FOR_MENTOR
      "Mentor"
    else
      "Trainer"
    end
  end

  def process_survey_answers(survey, is_trainer_survey, slot_id, survey_params)
    survey.survey_groups.each do |group|
      # Validate the group belongs to this survey
      unless group.survey_id == survey.id
        raise ArgumentError, "Survey group [#{group.id}] is not part of the survey"
      end

      if is_trainer_survey
        # Process each trainer for trainer surveys
        process_trainer_survey_group(group, survey, slot_id, survey_params)
      elsif group.type == SurveyGroup::TYPE_TRAINER
        # Process trainer-specific groups in student surveys
        process_student_trainer_group(group, survey, slot_id, survey_params)
      else
        # Process normal groups
        process_normal_group(group, survey, slot_id, survey_params)
      end
    end
  end

  def process_trainer_survey_group(group, survey, slot_id, survey_params)
    @trainers.each do |trainer|
      can_share_name = survey_params["share_name_#{trainer.id}"] == "1"

      group.survey_questions.each do |question|
        form_name = "question_#{question.id}_#{trainer.id}"
        response = survey_params[form_name]

        next if response.blank? && !question.is_required

        create_survey_answer(
          survey: survey,
          group: group,
          question: question,
          response: response,
          trainer_id: trainer.id,
          slot_id: slot_id,
          can_share_name: can_share_name
        )
      end
    end
  end

  def process_student_trainer_group(group, survey, slot_id, survey_params)
    @trainers.each do |trainer|
      group.survey_questions.each do |question|
        form_name = "question_#{question.id}_#{trainer.id}"
        response = survey_params[form_name]

        next if response.blank? && !question.is_required

        create_survey_answer(
          survey: survey,
          group: group,
          question: question,
          response: response,
          trainer_id: trainer.id,
          slot_id: slot_id,
          can_share_name: true
        )
      end
    end
  end

  def process_normal_group(group, survey, slot_id, survey_params)
    group.survey_questions.each do |question|
      form_name = "question_#{question.id}"
      response = survey_params[form_name]

      next if response.blank? && !question.is_required

      create_survey_answer(
        survey: survey,
        group: group,
        question: question,
        response: response,
        trainer_id: nil,
        slot_id: slot_id,
        can_share_name: true
      )
    end
  end

  def create_survey_answer(survey:, group:, question:, response:, trainer_id:, slot_id:, can_share_name:)
    SurveyAnswer.create!(
      person_id: current_user.id,
      survey_id: survey.id,
      survey_group_id: group.id,
      survey_question_id: question.id,
      response: response,
      trainer_id: trainer_id,
      slot_id: slot_id,
      can_share_name: can_share_name
    )
  end

  def validate_survey_responses
    errors = {}
    survey_params = params[:survey] || {}
    is_trainer_survey = (@survey.type == Survey::TRAINER)

    @survey.survey_groups.each do |group|
      if is_trainer_survey || group.type == SurveyGroup::TYPE_TRAINER
        @trainers.each do |trainer|
          group.survey_questions.select(&:is_required).each do |question|
            field_name = "question_#{question.id}_#{trainer.id}"
            errors[field_name] = "A response is required." if survey_params[field_name].blank?
          end
        end
      else
        group.survey_questions.select(&:is_required).each do |question|
          field_name = "question_#{question.id}"
          errors[field_name] = "A response is required." if survey_params[field_name].blank?
        end
      end
    end

    errors
  end
end
