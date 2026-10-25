# frozen_string_literal: true

# The Alphas' feedback on their mentors (Ember mentor/surveys and
# mentor/survey). Read-only. The report and per-mentor pages come from
# SurveyReportingConcern, shared with the training interface's own surveys.
#
# Three departures from upstream, all settled when this page was specced (see
# .scratch/mentoring-surveys/PLAN.md):
#
#   * The index is styled like the training surveys index -- each survey with
#     its audience, its reports, and whether anyone has answered -- rather than
#     upstream's bare Year/Title table. It still lists every year at once, which
#     upstream's does and the training index does not.
#   * Each mentor gets a page of their own, reached from the ranked table on
#     the report. Upstream has no per-mentor view at all: an Alpha survey's
#     feedback was readable only as one long report.
#   * Statistics columns show a real standard deviation, as on the training
#     pages. SurveyBuilder computes variance, which upstream printed under a
#     "Std. Dev." heading.
class Mentoring::SurveysController < ApplicationController
  include SurveyReportingConcern

  layout "mentoring"

  # Upstream Gate isMentor, which reaches the page. Reading it needs the survey
  # role below -- holding Mentor is not the same as managing Alpha surveys.
  authorize_role [Role::ADMIN, Role::MENTOR],
                 message: "Admin or Mentor role required to view Alpha surveys."

  # Only the index needs its own gate: the report pages run the same check
  # against the survey they loaded (authorize_survey_report below).
  before_action :authorize_survey_management, only: :index

  def index
    # Newest first: the season everyone is asking about is the last one.
    @surveys = Survey.find_for_query(type: Survey::ALPHA).reverse
  end

  private

  # --- loading ---------------------------------------------------------------

  # Only an Alpha survey loads here, which is what stops a training survey's
  # id from being read through the Mentor interface's looser gate. Both halves
  # of the pair are checked because nothing in the schema enforces it, and the
  # report gate keys on position_id -- admitting a mispaired row by type alone
  # would let it be read by a role the index gate turns away. Unknown ids get
  # the house friendly redirect, not a bare 404.
  def load_survey
    @survey = Survey.find_by(id: params[:survey_id])

    return if @survey&.type == Survey::ALPHA && @survey.position_id == Position::ALPHA

    redirect_to surveys_index_path, error: "Survey not found."
  end

  # --- authorization ---------------------------------------------------------

  # SurveyPolicy#indexForAll, narrowed to the one position this interface
  # shows. Survey.find_for_query filters row by row on the same check, so an
  # index that passed this gate can still come back empty -- but a Mentor who
  # does not manage surveys is told why instead of reading an empty page.
  def authorize_survey_management
    return if Survey.can_manage_surveys?(Current.person, Position::ALPHA)

    not_authorized_redirect("You are not authorized to view Alpha surveys.")
  end

  # SurveyPolicy#report, which for an Alpha survey is managers only: its
  # trainer fallback is denied outright when the survey sits at the Alpha
  # position, so a mentor may not read the whole class's feedback about the
  # mentor cadre.
  def authorize_survey_report
    return if @survey.can_manage_survey?(Current.person)

    not_authorized_redirect("You are not authorized to view this survey's feedback.")
  end

  # --- SurveyReportingConcern seams ------------------------------------------

  def surveys_index_path
    mentoring_surveys_path
  end

  def surveys_index_label
    "Alpha Surveys"
  end

  def survey_report_url(survey, report_id, **extra)
    mentoring_survey_report_path(survey.id, report_id, **extra)
  end

  def survey_person_url(person_id, **extra)
    mentoring_survey_mentor_path(@survey.id, person_id, **extra)
  end

  def csv_slug
    "alpha"
  end
end
