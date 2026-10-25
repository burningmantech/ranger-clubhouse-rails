# frozen_string_literal: true

# What the three survey management controllers share: the layout and the year
# floor, who may reach the section at all, how the survey a request names is
# loaded, the check that the person manages that particular survey, and the
# move that puts a group or a question one place up or down its line.
#
# Two gates, because they answer different questions. Holding a survey role
# opens the section; managing the cadre a survey belongs to is what lets
# someone change it. A Green Dot survey manager reaches the page and sees
# their own surveys there, and is turned away from the In-Person ones.
class Communication::SurveyManagementBaseController < ApplicationController
  include LineMoveConcern

  layout "communication"

  # Surveys have been kept in the Clubhouse since 2012.
  self.year_floor = 2012

  before_action :authorize_survey_management

  private

  def authorize_survey_management
    return if Survey.can_manage_any?(Current.person)

    not_authorized_redirect("Admin or a Survey Management role is required to manage surveys.")
  end

  # Which parameter names the survey. Groups and questions carry it as
  # :survey_id in their path; a survey's own pages carry it as :id, and say so
  # by overriding this.
  #
  # Read from one named place rather than the first of two that happens to be
  # set: params merges the query string, so on a survey's own routes -- where
  # :survey_id is no part of the path -- "?survey_id=9" would otherwise stand
  # in for the id in the URL, and a delete would take a survey the reader
  # never saw.
  def survey_id_param
    params[:survey_id]
  end

  # The survey a request names, or a friendly redirect. An id no one manages
  # and an id that does not exist are told apart, because the first is worth
  # explaining and the second is usually a stale link.
  def load_survey
    @survey = Survey.find_by(id: survey_id_param)

    unless @survey
      redirect_to communication_surveys_path, error: "Survey not found."
      return
    end

    return if @survey.can_manage_survey?(Current.person)

    not_authorized_redirect("You are not authorized to manage that survey.")
  end

  # The survey's own page, which is where every group and question edit
  # returns. The group it touched travels as a parameter rather than a
  # fragment: Turbo takes the page to go to from the response's URL, and a
  # fragment is not part of that, so "#group-7" would be dropped and the
  # reader left at the top of the page.
  def survey_page_path(group_id = nil)
    communication_survey_path(@survey, group: group_id)
  end
end
