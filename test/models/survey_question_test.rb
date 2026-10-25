# frozen_string_literal: true

require "test_helper"

# A question: the settings each kind keeps, and how it moves inside its group.
class SurveyQuestionTest < ActiveSupport::TestCase
  include SurveyTestHelper
  include ActiveSupport::Testing::TimeHelpers

  YEAR = 2026

  setup do
    travel_to Time.zone.local(YEAR, 8, 10, 12, 0, 0)
    Current.reset

    setup_survey_positions
    @survey = create_survey(position: @dirt)
    @group = create_survey_group(@survey, title: "The Venue")
  end

  teardown do
    Current.reset
    travel_back
  end

  test "a question answered from a list needs its choices" do
    question = SurveyQuestion.new(survey_id: @survey.id, survey_group_id: @group.id,
                                  type: SurveyQuestion::TYPE_OPTIONS, description: "Pick one",
                                  sort_index: 1)

    assert_not question.valid?
    assert_includes question.errors.full_messages,
                    "Choices are needed for a question answered from a list"

    question.options = "Yes\nNo"
    assert question.valid?, question.errors.full_messages.to_sentence
  end

  test "blank lines and stray spaces are dropped from the choices" do
    question = create_survey_question(@survey, @group, type: SurveyQuestion::TYPE_OPTIONS,
                                                      description: "Pick one",
                                                      options: " Yes \n\n  No\n")

    assert_equal "Yes\nNo", question.reload.options
    assert_equal ["Yes", "No"], question.option_list
  end

  test "a question keeps only the settings its own kind uses" do
    question = create_survey_question(@survey, @group, type: SurveyQuestion::TYPE_OPTIONS,
                                                      description: "Pick one", options: "Yes\nNo")

    # Choices left behind on a rating question would be read as the labels for
    # its ratings.
    question.update!(type: SurveyQuestion::TYPE_RATING, summarize_rating: true)
    assert_equal "", question.reload.options
    assert question.summarize_rating

    question.update!(type: SurveyQuestion::TYPE_TEXT)
    assert_not question.reload.summarize_rating
  end

  test "a kind of question this page does not know is refused" do
    question = SurveyQuestion.new(survey_id: @survey.id, survey_group_id: @group.id,
                                  type: "essay", description: "Discuss", sort_index: 1)

    assert_not question.valid?
    assert_includes question.errors.full_messages,
                    "Question type must be one of the kinds this page offers"
  end

  test "moving a question renumbers questions that shared a number" do
    first = create_survey_question(@survey, @group, description: "First", sort_index: 3)
    second = create_survey_question(@survey, @group, description: "Second", sort_index: 3)
    third = create_survey_question(@survey, @group, description: "Third", sort_index: 3)

    assert third.move("up")

    assert_equal [[first.id, 1], [third.id, 2], [second.id, 3]],
                 @group.survey_questions.reload.pluck(:id, :sort_index)
  end

  test "a question only moves among the questions of its own group" do
    other_group = create_survey_group(@survey, title: "Parting Thoughts")
    create_survey_question(@survey, other_group, description: "Theirs", sort_index: 1)
    mine = create_survey_question(@survey, @group, description: "Mine", sort_index: 1)

    assert_not mine.move("down")
  end

  test "deleting a question clears the answers given to it" do
    question = create_survey_question(@survey, @group)
    create_survey_answer(question, person: person(:inactive_ranger))

    question.destroy!

    assert_empty SurveyAnswer.where(survey_question_id: question.id)
  end
end
