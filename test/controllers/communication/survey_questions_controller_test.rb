# frozen_string_literal: true

require "test_helper"

# Communication > Survey Management: the questions inside a group, what each
# one asks, and the order they are asked in.
class Communication::SurveyQuestionsControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include SurveyTestHelper
  include DomIdTestHelper
  include ActiveSupport::Testing::TimeHelpers

  YEAR = 2026

  setup do
    travel_to Time.zone.local(YEAR, 8, 10, 12, 0, 0)
    Rails.cache.clear
    Current.reset

    setup_survey_positions
    setup_survey_managers
    @survey = create_survey(position: @dirt)
    @group = create_survey_group(@survey, title: "The Venue")
    sign_in_as(@dirt_manager)
  end

  teardown do
    Current.reset
    Rails.cache.clear
    travel_back
  end

  # ==========================================================================
  # Adding
  # ==========================================================================

  test "a question is added to the end of its group" do
    create_survey_question(@survey, @group, description: "First", sort_index: 3)

    assert_difference "SurveyQuestion.count", 1 do
      post communication_survey_questions_path(@survey), params: {
        survey_question: { survey_group_id: @group.id, type: SurveyQuestion::TYPE_TEXT,
                           description: "What did you think?" }
      }
    end

    question = SurveyQuestion.order(:id).last
    assert_redirected_to communication_survey_path(@survey, group: @group.id)
    assert_equal 4, question.sort_index
    assert_equal @survey.id, question.survey_id
    assert_equal @group.id, question.survey_group_id
  end

  test "adding a question is recorded in the action log" do
    assert_difference "ActionLog.where(event: 'survey-question-create').count", 1 do
      post communication_survey_questions_path(@survey), params: {
        survey_question: { survey_group_id: @group.id, type: SurveyQuestion::TYPE_TEXT,
                           description: "What did you think?" }
      }
    end
  end

  test "a question answered from a list needs its choices" do
    assert_no_difference "SurveyQuestion.count" do
      post communication_survey_questions_path(@survey), params: {
        survey_question: { survey_group_id: @group.id, type: SurveyQuestion::TYPE_OPTIONS,
                           description: "Pick one", options: "  \n \n" }
      }
    end

    assert_response :unprocessable_entity
    assert_match "Choices are needed for a question answered from a list", response.body
  end

  test "blank lines are dropped from the choices" do
    post communication_survey_questions_path(@survey), params: {
      survey_question: { survey_group_id: @group.id, type: SurveyQuestion::TYPE_OPTIONS,
                         description: "Pick one", options: " Yes \n\n No \n" }
    }

    assert_equal "Yes\nNo", SurveyQuestion.order(:id).last.options
  end

  test "a rating question keeps only the settings a rating uses" do
    post communication_survey_questions_path(@survey), params: {
      survey_question: { survey_group_id: @group.id, type: SurveyQuestion::TYPE_RATING,
                         description: "Rate the venue", summarize_rating: "1",
                         options: "Yes\nNo" }
    }

    question = SurveyQuestion.order(:id).last
    assert question.summarize_rating
    assert_equal "", question.options
  end

  test "a text question does not keep a summarize setting" do
    post communication_survey_questions_path(@survey), params: {
      survey_question: { survey_group_id: @group.id, type: SurveyQuestion::TYPE_TEXT,
                         description: "Tell us more", summarize_rating: "1" }
    }

    assert_not SurveyQuestion.order(:id).last.summarize_rating
  end

  test "a question may not be filed under another survey's group" do
    other = create_survey(position: @dirt, type: Survey::TRAINER, title: "Another")
    other_group = create_survey_group(other)

    assert_no_difference "SurveyQuestion.count" do
      post communication_survey_questions_path(@survey), params: {
        survey_question: { survey_group_id: other_group.id, type: SurveyQuestion::TYPE_TEXT,
                           description: "Sneaky" }
      }
    end

    assert_redirected_to communication_survey_path(@survey)
    assert_equal "Group not found.", flash[:error]
  end

  test "a non-hash survey_question param is refused like a missing group rather than raising" do
    assert_no_difference "SurveyQuestion.count" do
      post communication_survey_questions_path(@survey), params: { survey_question: "x" }
    end

    assert_redirected_to communication_survey_path(@survey)
    assert_equal "Group not found.", flash[:error]
  end

  test "the add form refuses a group from another survey" do
    other = create_survey(position: @dirt, type: Survey::TRAINER, title: "Another")
    other_group = create_survey_group(other)

    get new_communication_survey_question_path(@survey, group_id: other_group.id)

    assert_redirected_to communication_survey_path(@survey)
    assert_equal "Group not found.", flash[:error]
  end

  # ==========================================================================
  # Editing and deleting
  # ==========================================================================

  test "the add form opens and says which group it is adding to" do
    get new_communication_survey_question_path(@survey, group_id: @group.id)

    assert_response :success
    assert_select "input[name=?][value=?]", "survey_question[survey_group_id]", @group.id.to_s
    assert_match @group.title, response.body
  end

  test "the edit form opens with the question in it" do
    question = create_survey_question(@survey, @group, description: "How was it?",
                                                       type: SurveyQuestion::TYPE_OPTIONS,
                                                       options: "Yes\nNo")

    get edit_communication_survey_question_path(@survey, question)

    assert_response :success
    assert_select "textarea[name=?]", "survey_question[description]", text: /How was it\?/
    assert_select "textarea[name=?]", "survey_question[options]"
  end

  test "a question is reworded" do
    question = create_survey_question(@survey, @group, description: "How was it?")

    patch communication_survey_question_path(@survey, question), params: {
      survey_question: { type: question.type, description: "How did it go?", is_required: "1" }
    }

    assert_redirected_to communication_survey_path(@survey, group: @group.id)
    question.reload
    assert_equal "How did it go?", question.description
    assert question.is_required
  end

  test "a question that cannot be saved comes back as a form, not a crash" do
    question = create_survey_question(@survey, @group, description: "How was it?")

    patch communication_survey_question_path(@survey, question), params: {
      survey_question: { type: SurveyQuestion::TYPE_OPTIONS, description: question.description,
                         options: "" }
    }

    assert_response :unprocessable_entity
    assert_match "Choices are needed for a question answered from a list", response.body
    assert_equal SurveyQuestion::TYPE_TEXT, question.reload.type
  end

  # An answer means something different under each kind: a written answer read
  # as a rating counts as nothing.
  test "a question's kind is settled once people have answered it" do
    question = create_survey_question(@survey, @group, type: SurveyQuestion::TYPE_OPTIONS,
                                                      description: "Pick one", options: "Yes\nNo")
    create_survey_answer(question, person: @outsider, response: "Yes")

    patch communication_survey_question_path(@survey, question), params: {
      survey_question: { type: SurveyQuestion::TYPE_RATING, description: question.description }
    }

    assert_response :unprocessable_entity
    assert_match "Question type cannot be changed once people have answered", response.body
    question.reload
    assert_equal SurveyQuestion::TYPE_OPTIONS, question.type
    assert_equal "Yes\nNo", question.options
  end

  test "deleting a question takes its answers" do
    question = create_survey_question(@survey, @group)
    create_survey_answer(question, person: @outsider)

    assert_difference ["SurveyQuestion.count", "SurveyAnswer.count"], -1 do
      delete communication_survey_question_path(@survey, question)
    end

    assert_redirected_to communication_survey_path(@survey, group: @group.id)
  end

  test "a question belonging to another survey is not found" do
    other = create_survey(position: @dirt, type: Survey::TRAINER, title: "Another")
    other_group = create_survey_group(other)
    question = create_survey_question(other, other_group, description: "Theirs")

    patch communication_survey_question_path(@survey, question), params: {
      survey_question: { type: question.type, description: "Mine now" }
    }

    assert_redirected_to communication_survey_path(@survey)
    assert_equal "Question not found.", flash[:error]
    assert_equal "Theirs", question.reload.description
  end

  test "another cadre's survey may not be given questions" do
    survey = create_survey(position: @green_dot, title: "Theirs")
    group = create_survey_group(survey)

    assert_no_difference "SurveyQuestion.count" do
      post communication_survey_questions_path(survey), params: {
        survey_question: { survey_group_id: group.id, type: SurveyQuestion::TYPE_TEXT,
                           description: "Sneaky" }
      }
    end

    assert_redirected_to me_root_path
    assert_equal "You are not authorized to manage that survey.", flash[:error]
  end

  # ==========================================================================
  # Order
  # ==========================================================================

  test "moving a question renumbers the group, including numbers that were shared" do
    # Questions on file share numbers with each other; the id decides which
    # comes first, and a move puts the whole group back in step.
    first = create_survey_question(@survey, @group, description: "First", sort_index: 3)
    second = create_survey_question(@survey, @group, description: "Second", sort_index: 3)
    third = create_survey_question(@survey, @group, description: "Third", sort_index: 3)

    patch move_communication_survey_question_path(@survey, third, direction: "up")

    assert_redirected_to communication_survey_path(@survey, group: @group.id)
    assert_equal [[first.id, 1], [third.id, 2], [second.id, 3]],
                 @group.survey_questions.reload.pluck(:id, :sort_index)
  end

  test "a question only moves within its own group" do
    other_group = create_survey_group(@survey, title: "Parting Thoughts")
    mine = create_survey_question(@survey, @group, description: "Mine", sort_index: 1)
    theirs = create_survey_question(@survey, other_group, description: "Theirs", sort_index: 1)

    patch move_communication_survey_question_path(@survey, mine, direction: "down")

    assert_equal "That question is already at that end.", flash[:info]
    assert_equal 1, mine.reload.sort_index
    assert_equal 1, theirs.reload.sort_index
  end
end
