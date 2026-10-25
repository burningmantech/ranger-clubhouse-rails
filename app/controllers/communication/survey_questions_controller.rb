# frozen_string_literal: true

# The questions inside one group of one survey.
#
# A question is always reached through its survey, and the group it is filed
# under is looked up through that survey too, so a question cannot be moved
# into a group belonging to someone else's survey.
class Communication::SurveyQuestionsController < Communication::SurveyManagementBaseController
  before_action :load_survey
  before_action :load_question, only: [:edit, :update, :destroy, :move]

  def new
    @group = find_group(params[:group_id])
    return unless @group

    @question = @group.survey_questions.new(survey_id: @survey.id, type: SurveyQuestion::TYPE_TEXT)
  end

  def create
    @group = find_group(scoped_params(:survey_question, :survey_group_id)[:survey_group_id])
    return unless @group

    @question = @group.survey_questions.new(question_params)
    # A new question joins the end of its group; moving it is a separate step.
    @question.assign_attributes(survey_id: @survey.id, sort_index: @question.next_sort_index)

    return render(:new, status: :unprocessable_entity) unless @question.save

    redirect_to survey_page_path(@group.id), success: "Question added."
  end

  def edit
  end

  def update
    return render(:edit, status: :unprocessable_entity) unless @question.update(question_params)

    redirect_to survey_page_path(@group.id), success: "Question updated."
  end

  def destroy
    @question.destroy!

    redirect_to survey_page_path(@group.id), success: "Question deleted."
  end

  # One step up or down inside its own group. The whole group is renumbered,
  # so questions that shared a number come back in step.
  def move
    move_in_line(@question, survey_page_path(@group.id), "The question order has been updated.",
                 "That question is already at that end.")
  end

  private

  def load_question
    @question = @survey.survey_questions.includes(:survey_group).find_by(id: params[:id])

    unless @question
      redirect_to survey_page_path, error: "Question not found."
      return
    end

    @group = @question.survey_group
  end

  # A group of this survey, or a redirect. Anything else -- a missing id, or a
  # group belonging to another survey -- lands back on the survey page.
  def find_group(id)
    group = @survey.survey_groups.find_by(id:)
    return group if group

    redirect_to survey_page_path, error: "Group not found."
    nil
  end

  def question_params
    params.expect(survey_question: [:type, :description, :is_required, :options,
                                    :summarize_rating])
  end
end
