# frozen_string_literal: true

require "test_helper"

# The group heading on the survey a person is answering. Descriptions carry
# simple formatting, and printing them as text put the tags on the screen.
class Me::SurveyQuestionGroupPartialTest < ActionView::TestCase
  include ApplicationHelper
  include UiComponents::UiSectionHelper

  Group = Struct.new(:id, :title, :description, :survey_questions)

  test "formatting in a group description is rendered, not printed" do
    group = Group.new(1, "The Venue", "Answer this <b>only</b> if you attended.", [])

    render partial: "me/surveys/question_group",
           locals: { group:, trainer: nil, trainer_name: nil, show_trainer_photo: false,
                     is_trainer_survey: false, form: nil }

    # A div, not a paragraph: the allowed formatting includes lists, which a
    # paragraph cannot hold.
    assert_select "div b", text: "only"
    assert_no_match(/&lt;b&gt;/, rendered)
  end

  test "a description written with a script tag has it stripped" do
    group = Group.new(1, "The Venue", "Careful<script>alert(1)</script>", [])

    render partial: "me/surveys/question_group",
           locals: { group:, trainer: nil, trainer_name: nil, show_trainer_photo: false,
                     is_trainer_survey: false, form: nil }

    assert_no_match(/script/, rendered)
  end
end
