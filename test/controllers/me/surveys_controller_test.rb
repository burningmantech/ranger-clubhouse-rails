# frozen_string_literal: true

require "test_helper"

# Submitting the Alpha survey from /me: the answers replace the person's old
# ones, and a request that does not carry a set of answers changes nothing.
class Me::SurveysControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include SurveyTestHelper

  YEAR = 2025

  setup do
    setup_survey_positions
    @alpha_person = person(:alpha_ranger)
    Timesheet.create!(person_id: @alpha_person.id, position_id: Position::ALPHA,
                      on_duty: Time.zone.local(YEAR, 8, 25, 9), off_duty: Time.zone.local(YEAR, 8, 25, 17),
                      additional_notes: "Alpha shift")

    @survey = create_survey(position: @alpha, type: Survey::ALPHA, year: YEAR)
    @question = create_survey_question(@survey, create_survey_group(@survey))
    @old_answer = create_survey_answer(@question, person: @alpha_person)

    sign_in_as(@alpha_person)
  end

  test "submitting the survey replaces the old answers" do
    post me_surveys_path(type: Survey::ALPHA, year: YEAR),
         params: { survey: { "question_#{@question.id}" => "Loved it." } }

    assert_redirected_to me_root_path
    assert_equal "Survey responses saved.", flash[:success]
    assert_not SurveyAnswer.exists?(@old_answer.id)
    assert_equal "Loved it.", SurveyAnswer.find_by(survey_question_id: @question.id, person_id: @alpha_person.id).response
  end

  test "a survey scope that is not a set of answers is refused before the old answers are cleared" do
    post me_surveys_path(type: Survey::ALPHA, year: YEAR), params: { survey: "x" }

    assert_redirected_to me_root_path
    assert_equal "An error occurred while saving your responses. Please try again.", flash[:error]
    assert SurveyAnswer.exists?(@old_answer.id)
  end

  # lexxy-content is what gives a saved list its markers and a table its borders.
  # The management page's preview has it, so without it here the people
  # answering saw something the person who wrote the survey never did.
  test "the prologue and the epilogue are shown in the container saved text is styled by" do
    @survey.update!(prologue: "<ul><li>Read this first</li></ul>",
                    epilogue: "<figure><table><tbody><tr><td>Thank you</td></tr></tbody></table></figure>")

    get me_surveys_path(type: Survey::ALPHA, year: YEAR)

    assert_response :success
    assert_select "[role=alert] .lexxy-content li", text: "Read this first"
    assert_select ".lexxy-content table td", text: "Thank you"
  end
end
