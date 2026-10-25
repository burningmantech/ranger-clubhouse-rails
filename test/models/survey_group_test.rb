# frozen_string_literal: true

require "test_helper"

# A group of questions: what it will accept, and how it moves in the line of
# groups a survey asks.
class SurveyGroupTest < ActiveSupport::TestCase
  include SurveyTestHelper
  include ActiveSupport::Testing::TimeHelpers

  YEAR = 2026

  setup do
    travel_to Time.zone.local(YEAR, 8, 10, 12, 0, 0)
    Current.reset

    setup_survey_positions
    @survey = create_survey(position: @dirt)
  end

  teardown do
    Current.reset
    travel_back
  end

  test "a group saved without a description keeps empty text rather than failing" do
    group = SurveyGroup.create!(survey_id: @survey.id, title: "The Venue")

    assert_equal "", group.reload.description
    assert_equal SurveyGroup::TYPE_NORMAL, group.type
    assert_equal 1, group.sort_index
  end

  test "a group reported on its own needs a name for that report" do
    group = SurveyGroup.new(survey_id: @survey.id, title: "Manual Review",
                            type: SurveyGroup::TYPE_SUMMARY)

    assert_not group.valid?
    assert_includes group.errors.full_messages,
                    "Report title is needed for a group that has a report of its own"

    group.report_title = "Manual Review"
    assert group.valid?, group.errors.full_messages.to_sentence
  end

  test "a standard group needs no report title" do
    group = SurveyGroup.new(survey_id: @survey.id, title: "The Venue",
                            type: SurveyGroup::TYPE_NORMAL)

    assert group.valid?, group.errors.full_messages.to_sentence
  end

  test "the next group in a line takes the number after the last" do
    create_survey_group(@survey, title: "First", sort_index: 4)

    assert_equal 5, @survey.survey_groups.new.next_sort_index
  end

  test "moving a group renumbers a line that skipped numbers" do
    first = create_survey_group(@survey, title: "First", sort_index: 1)
    second = create_survey_group(@survey, title: "Second", sort_index: 4)
    third = create_survey_group(@survey, title: "Third", sort_index: 7)

    assert third.move("up")

    assert_equal [[first.id, 1], [third.id, 2], [second.id, 3]],
                 @survey.survey_groups.reload.pluck(:id, :sort_index)
  end

  test "a group at either end of the line stays put" do
    first = create_survey_group(@survey, title: "First", sort_index: 1)
    last = create_survey_group(@survey, title: "Last", sort_index: 2)

    assert_not first.move("up")
    assert_not last.move("down")
    assert_not first.move("sideways")
    assert_equal [1, 2], @survey.survey_groups.reload.pluck(:sort_index)
  end

  test "a group only moves among the groups of its own survey" do
    other = create_survey(position: @dirt, type: Survey::TRAINER, title: "Another")
    create_survey_group(other, title: "Theirs", sort_index: 1)
    mine = create_survey_group(@survey, title: "Mine", sort_index: 1)

    assert_not mine.move("down")
  end

  test "deleting a group clears its questions and their answers" do
    group = create_survey_group(@survey)
    question = create_survey_question(@survey, group)
    create_survey_answer(question, person: person(:inactive_ranger))

    group.destroy!

    assert_empty SurveyQuestion.where(survey_group_id: group.id)
    assert_empty SurveyAnswer.where(survey_group_id: group.id)
  end
end
