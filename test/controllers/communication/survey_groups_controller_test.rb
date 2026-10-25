# frozen_string_literal: true

require "test_helper"

# Communication > Survey Management: the groups of questions inside a survey,
# and the order they are asked in.
class Communication::SurveyGroupsControllerTest < ActionDispatch::IntegrationTest
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

  test "a group is added to the end of the survey" do
    create_survey_group(@survey, title: "The Venue", sort_index: 4)

    assert_difference "SurveyGroup.count", 1 do
      post communication_survey_groups_path(@survey), params: {
        survey_group: { title: "Parting Thoughts", type: SurveyGroup::TYPE_NORMAL }
      }
    end

    group = SurveyGroup.order(:id).last
    assert_redirected_to communication_survey_path(@survey, group: group.id)
    assert_equal 5, group.sort_index
    assert_equal @survey.id, group.survey_id
  end

  test "adding a group is recorded in the action log" do
    assert_difference "ActionLog.where(event: 'survey-group-create').count", 1 do
      post communication_survey_groups_path(@survey), params: {
        survey_group: { title: "The Venue", type: SurveyGroup::TYPE_NORMAL }
      }
    end
  end

  test "a group with its own report needs a name for it" do
    assert_no_difference "SurveyGroup.count" do
      post communication_survey_groups_path(@survey), params: {
        survey_group: { title: "Manual Review", type: SurveyGroup::TYPE_SUMMARY, report_title: "" }
      }
    end

    assert_response :unprocessable_entity
    assert_match "Report title is needed for a group that has a report of its own", response.body
  end

  test "a report title longer than the column holds is a form error" do
    assert_no_difference "SurveyGroup.count" do
      post communication_survey_groups_path(@survey), params: {
        survey_group: { title: "Manual Review", type: SurveyGroup::TYPE_SUMMARY,
                        report_title: "R" * 500 }
      }
    end

    assert_response :unprocessable_entity
    assert_match "Report title is too long", response.body
  end

  test "a group with no title is refused" do
    assert_no_difference "SurveyGroup.count" do
      post communication_survey_groups_path(@survey), params: {
        survey_group: { title: "", type: SurveyGroup::TYPE_NORMAL }
      }
    end

    assert_response :unprocessable_entity
    assert_select "#form-error-summary", text: /Group title can't be blank/
  end

  # ==========================================================================
  # Editing and deleting
  # ==========================================================================

  test "the add form opens" do
    get new_communication_survey_group_path(@survey)

    assert_response :success
    assert_select "input[name=?]", "survey_group[title]"
  end

  test "the edit form opens with the group's details in it" do
    group = create_survey_group(@survey, title: "The Venue", type: SurveyGroup::TYPE_SUMMARY,
                                         report_title: "Venue Summary")

    get edit_communication_survey_group_path(@survey, group)

    assert_response :success
    assert_select "input[name=?][value=?]", "survey_group[title]", "The Venue"
    assert_select "input[name=?][value=?]", "survey_group[report_title]", "Venue Summary"
  end

  test "a group is renamed" do
    group = create_survey_group(@survey, title: "The Venue")

    patch communication_survey_group_path(@survey, group), params: {
      survey_group: { title: "The Location", type: group.type }
    }

    assert_redirected_to communication_survey_path(@survey, group: group.id)
    assert_equal "The Location", group.reload.title
  end

  test "a group that cannot be saved comes back as a form, not a crash" do
    group = create_survey_group(@survey, title: "The Venue")

    patch communication_survey_group_path(@survey, group), params: {
      survey_group: { title: "", type: group.type }
    }

    assert_response :unprocessable_entity
    assert_select "#form-error-summary", text: /Group title can't be blank/
    assert_equal "The Venue", group.reload.title
  end

  test "deleting a group takes its questions and their answers" do
    group = create_survey_group(@survey)
    question = create_survey_question(@survey, group)
    create_survey_answer(question, person: @outsider)

    assert_difference ["SurveyGroup.count", "SurveyQuestion.count", "SurveyAnswer.count"], -1 do
      delete communication_survey_group_path(@survey, group)
    end

    assert_redirected_to communication_survey_path(@survey)
    assert_match "and its questions deleted", flash[:success]
  end

  test "a group belonging to another survey is not found" do
    other = create_survey(position: @dirt, type: Survey::TRAINER, title: "Another")
    group = create_survey_group(other)

    patch communication_survey_group_path(@survey, group), params: {
      survey_group: { title: "Renamed", type: group.type }
    }

    assert_redirected_to communication_survey_path(@survey)
    assert_equal "Group not found.", flash[:error]
    assert_not_equal "Renamed", group.reload.title
  end

  test "another cadre's survey may not be given groups" do
    survey = create_survey(position: @green_dot)

    assert_no_difference "SurveyGroup.count" do
      post communication_survey_groups_path(survey), params: {
        survey_group: { title: "The Venue", type: SurveyGroup::TYPE_NORMAL }
      }
    end

    assert_redirected_to me_root_path
  end

  test "a group's kind is settled once its questions have been answered" do
    group = create_survey_group(@survey, title: "The Venue")
    question = create_survey_question(@survey, group)
    create_survey_answer(question, person: @outsider)

    patch communication_survey_group_path(@survey, group), params: {
      survey_group: { title: group.title, type: SurveyGroup::TYPE_TRAINER }
    }

    assert_response :unprocessable_entity
    assert_match "Group type cannot be changed once people have answered", response.body
    assert_equal SurveyGroup::TYPE_NORMAL, group.reload.type
  end

  # ==========================================================================
  # Order
  # ==========================================================================

  test "moving a group up renumbers the whole line" do
    # The numbers on file skip: they are what a season of edits left behind.
    first = create_survey_group(@survey, title: "First", sort_index: 1)
    second = create_survey_group(@survey, title: "Second", sort_index: 4)
    third = create_survey_group(@survey, title: "Third", sort_index: 7)

    patch move_communication_survey_group_path(@survey, third, direction: "up")

    assert_redirected_to communication_survey_path(@survey, group: third.id)
    assert_equal "The group order has been updated.", flash[:success]
    assert_equal [[first.id, 1], [third.id, 2], [second.id, 3]],
                 @survey.survey_groups.reload.pluck(:id, :sort_index)
  end

  test "moving a group down swaps it with the one below" do
    first = create_survey_group(@survey, title: "First", sort_index: 1)
    second = create_survey_group(@survey, title: "Second", sort_index: 2)

    patch move_communication_survey_group_path(@survey, first, direction: "down")

    assert_equal [[second.id, 1], [first.id, 2]],
                 @survey.survey_groups.reload.pluck(:id, :sort_index)
  end

  test "a group at the end of the line does not move" do
    first = create_survey_group(@survey, title: "First", sort_index: 1)
    create_survey_group(@survey, title: "Second", sort_index: 2)

    patch move_communication_survey_group_path(@survey, first, direction: "up")

    assert_redirected_to communication_survey_path(@survey, group: first.id)
    assert_equal "\"First\" is already at that end.", flash[:info]
    assert_equal 1, first.reload.sort_index
  end

  # A row written by the other application, which does not require a report
  # title, must not make the whole line unmovable.
  test "a line still moves when a group would not pass today's rules" do
    first = create_survey_group(@survey, title: "First", sort_index: 1)
    second = create_survey_group(@survey, title: "Second", sort_index: 2)
    second.update_columns(type: SurveyGroup::TYPE_SUMMARY, report_title: "")

    patch move_communication_survey_group_path(@survey, second, direction: "up")

    assert_redirected_to communication_survey_path(@survey, group: second.id)
    assert_equal "The group order has been updated.", flash[:success]
    assert_equal [[second.id, 1], [first.id, 2]],
                 @survey.survey_groups.reload.pluck(:id, :sort_index)
  end

  test "a direction that is neither up nor down moves nothing" do
    first = create_survey_group(@survey, title: "First", sort_index: 1)
    create_survey_group(@survey, title: "Second", sort_index: 2)

    patch move_communication_survey_group_path(@survey, first, direction: "sideways")

    assert_equal 1, first.reload.sort_index
    assert flash[:info].present?
  end
end
