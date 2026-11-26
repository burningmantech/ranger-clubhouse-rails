# frozen_string_literal: true

require "test_helper"

# The link from a survey to the page its answers are read on is offered only to
# a reader that page admits.
class Communication::SurveysHelperTest < ActionView::TestCase
  include Communication::SurveysHelper

  # The controller's helper_method, answered from the roles a test sets.
  def has_role?(roles) = @roles.intersect?(Array(roles))

  test "the Alpha feedback link follows the Mentoring surveys page's gate" do
    survey = Survey.new(type: Survey::ALPHA)

    Mentoring::SurveysController.authorized_roles.each do |role|
      @roles = [role]
      assert_equal mentoring_surveys_path, survey_feedback_path(survey), "role #{role} opens the page"
    end

    @roles = [Role::VC]
    assert_nil survey_feedback_path(survey)
  end
end
