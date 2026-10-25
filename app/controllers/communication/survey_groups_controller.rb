# frozen_string_literal: true

# The groups of questions inside one survey. A group is a heading with its own
# questions under it, and the survey is answered a group at a time.
#
# Every action here is gated by the survey, and every group is looked up
# through it, which is what stops another survey's group from being edited
# from this one's page.
class Communication::SurveyGroupsController < Communication::SurveyManagementBaseController
  before_action :load_survey
  before_action :load_group, only: [:edit, :update, :destroy, :move]

  def new
    @group = @survey.survey_groups.new(type: SurveyGroup::TYPE_NORMAL)
  end

  def create
    @group = @survey.survey_groups.new(group_params)
    # A new group joins the end of the line; moving it is a separate step.
    @group.sort_index = @group.next_sort_index

    return render(:new, status: :unprocessable_entity) unless @group.save

    redirect_to survey_page_path(@group.id), success: "Group added."
  end

  def edit
  end

  def update
    return render(:edit, status: :unprocessable_entity) unless @group.update(group_params)

    redirect_to survey_page_path(@group.id), success: "Group updated."
  end

  def destroy
    title = @group.title
    @group.destroy!

    redirect_to survey_page_path, success: "\"#{title}\" and its questions deleted."
  end

  # One step up or down the line. The whole line is renumbered, so an order
  # that skipped or repeated numbers comes back in step.
  def move
    move_in_line(@group, survey_page_path(@group.id), "The group order has been updated.",
                 "\"#{@group.title}\" is already at that end.")
  end

  private

  def load_group
    @group = @survey.survey_groups.find_by(id: params[:id])
    return if @group

    redirect_to survey_page_path, error: "Group not found."
  end

  def group_params
    params.expect(survey_group: [:title, :description, :type, :report_title])
  end
end
