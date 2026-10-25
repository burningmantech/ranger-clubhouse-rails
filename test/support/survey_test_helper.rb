# frozen_string_literal: true

# Builders for the survey rows a test needs. There are no survey fixtures: a
# survey is only meaningful together with its groups, its questions, and the
# positions they hang off, so each test builds the shape it is about.
module SurveyTestHelper
  include ArtMentoringTestHelper

  # The positions surveys hang off. Created rather than fixtured because the
  # rules key on the ids the Clubhouse names in code.
  def setup_survey_positions
    @dirt = Position.create!(id: Position::TRAINING, title: "Training",
                             type: Position::TYPE_TRAINING, active: true)
    # Green Dot as an ART mentoring training: its flags are how Training finds
    # the mentor and mentee positions a Green Dot survey may sit at.
    setup_art_mentoring
    @green_dot, @gd_mentor, @gd_mentee = @training, @mentor_position, @mentee_position
    @alpha = Position.create!(id: Position::ALPHA, title: "Alpha", type: "Mentoring", active: true)
    # Alpha's cadre position: the Alpha survey permission reaches this one too.
    @mentor = Position.create!(id: Position::MENTOR, title: "Mentor", type: "Mentoring", active: true)
  end

  # The survey permissions and the people who hold them: the flat one for
  # In-Person Training, one composed for the Green Dot cadre, one composed for
  # the Alphas, and an admin -- plus someone with none of them.
  def setup_survey_managers
    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::SURVEY_MANAGEMENT_TRAINING, "Survey Management")
    ensure_role(Role::SURVEY_MANAGEMENT_BASE | Position::GREEN_DOT_TRAINING, "Green Dot Survey Mgmt")
    ensure_role(Role::SURVEY_MANAGEMENT_BASE | Position::ALPHA, "Alpha Survey Mgmt")

    # Manages In-Person Training surveys, and nothing else.
    @dirt_manager = person(:echelon_ranger)
    grant_role(@dirt_manager, Role::SURVEY_MANAGEMENT_TRAINING)

    # Manages the Green Dot cadre's surveys: the training, and its mentors
    # and mentees.
    @art_manager = person(:retired_ranger)
    grant_role(@art_manager, Role::SURVEY_MANAGEMENT_BASE | Position::GREEN_DOT_TRAINING)

    # Manages the Alphas' survey, and the Mentor position that goes with it.
    @alpha_manager = person(:alpha_ranger)
    grant_role(@alpha_manager, Role::SURVEY_MANAGEMENT_BASE | Position::ALPHA)

    @admin = person(:active_ranger)
    grant_role(@admin, Role::ADMIN)

    @outsider = person(:inactive_ranger)
  end

  def create_survey(position:, type: Survey::TRAINING, year: Current.year, active: true,
                    mentoring_position: nil, title: nil, prologue: "Thank you.", epilogue: "Thanks again.")
    Survey.create!(year:, type:, active:,
                   position_id: position.id,
                   mentoring_position_id: mentoring_position&.id,
                   title: title || "#{year} #{position.title} Survey",
                   prologue:, epilogue:)
  end

  def create_survey_group(survey, title: "The Venue", type: SurveyGroup::TYPE_NORMAL,
                          sort_index: nil, description: "", report_title: "")
    SurveyGroup.create!(survey_id: survey.id, title:, type:, description:, report_title:,
                        sort_index: sort_index || survey.survey_groups.maximum(:sort_index).to_i + 1)
  end

  def create_survey_question(survey, group, description: "How was it?",
                             type: SurveyQuestion::TYPE_TEXT, sort_index: nil,
                             is_required: false, options: "", summarize_rating: false)
    SurveyQuestion.create!(survey_id: survey.id, survey_group_id: group.id, description:, type:,
                           is_required:, options:, summarize_rating:,
                           sort_index: sort_index || group.survey_questions.maximum(:sort_index).to_i + 1)
  end

  def create_survey_answer(question, person:, response: "It was fine.", slot: nil, trainer: nil)
    SurveyAnswer.create!(survey_id: question.survey_id, survey_group_id: question.survey_group_id,
                         survey_question_id: question.id, person_id: person.id,
                         trainer_id: trainer&.id, slot_id: slot&.id, response:, can_share_name: true)
  end
end
