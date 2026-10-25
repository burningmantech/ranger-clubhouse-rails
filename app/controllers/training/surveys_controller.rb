# frozen_string_literal: true

# Survey feedback reports for a training position (Ember
# training/:position_id/survey, pluralized here). Read-only; slug resolution,
# the TrainingPolicy view gate, and @year come from the base controller. The
# report and per-trainer pages themselves live in SurveyReportingConcern,
# shared with the Mentors' Alpha surveys.
#
# Three deviations from upstream, all deliberate:
#
# 1. One index covers the training, mentor, and mentee audiences that upstream
#    reached through three sidebar links and a ?position_id= query parameter.
#    One survey-management role already covers all three.
# 2. Trainer feedback is a ranked table drilling into a page per trainer,
#    instead of a stack of collapsed accordions -- In-Person Training runs 40+
#    trainers a year, and the per-trainer page is what feedback delivery needs.
# 3. Statistics columns show a real standard deviation. SurveyBuilder computes
#    variance; upstream printed it under a "Std. Dev." heading, and its CSV
#    exported (mean / 7) / 100 for the same column.
class Training::SurveysController < Training::BaseController
  include SurveyReportingConcern

  # One audience of surveys on the index: the training itself, or its mentor
  # or mentee position.
  Section = Struct.new(:title, :position_title, :surveys, keyword_init: true)

  before_action :authorize_survey_management, only: :index

  def index
    @sections = build_sections
  end

  private

  # --- loading ---------------------------------------------------------------

  # One section per audience, in the order the interface presents them. Every
  # section renders even when empty -- "no mentor surveys this year" is an
  # answer, and a silently missing section reads as a bug.
  def build_sections
    position_ids = Training.survey_position_ids(@training)
    titles = Position.titles_by_id(position_ids)

    position_ids.map do |position_id|
      Section.new(
        title: section_title(position_id),
        position_title: titles[position_id],
        surveys: Survey.find_for_query(year: @year, position_id:, include_slots: true)
      )
    end
  end

  def section_title(position_id)
    case position_id
    when Training.mentor_position_id(@training) then "Mentor Surveys"
    when Training.mentee_position_id(@training) then "Mentee Surveys"
    else "Training Surveys"
    end
  end

  # The survey must belong to this training's family of positions, which is
  # what stops another training's survey id from loading under this slug.
  # Unknown ids get the house friendly redirect, not a bare 404.
  def load_survey
    @survey = Survey.find_by(id: params[:survey_id])

    return if @survey && Training.survey_position_ids(@training).include?(@survey.position_id)

    redirect_to surveys_index_path, error: "Survey not found."
  end

  # --- authorization ---------------------------------------------------------

  # SurveyPolicy#indexForPosition. The same list drives the menu item's
  # visibility (TrainingMenu), so what the menu offers and what this admits
  # cannot drift.
  def authorize_survey_management
    return if has_role?(Training.survey_management_roles(@training))

    not_authorized_redirect("You are not authorized to view #{@training.title} surveys.")
  end

  # SurveyPolicy#report: managers always, trainers for feedback about their
  # own training. Trainer-on-trainer surveys stay managers-only
  # (SurveyPolicy#allTrainersReport) -- trainers may not read what their peers
  # said about each other.
  def authorize_survey_report
    return if @survey.can_manage_survey?(Current.person)
    return if !trainer_survey? && @survey.is_trainer_for_survey?(Current.person)

    not_authorized_redirect("You are not authorized to view this survey's feedback.")
  end

  # --- SurveyReportingConcern seams ------------------------------------------

  def surveys_index_path
    training_surveys_path(training_slug, year: @year)
  end

  def surveys_index_label
    "#{@year} Surveys"
  end

  def survey_report_url(survey, report_id, **extra)
    training_survey_report_path(training_slug, survey.id, report_id, year: @year, **extra)
  end

  def survey_person_url(person_id, **extra)
    training_survey_trainer_path(training_slug, @survey.id, person_id, year: @year, **extra)
  end

  def csv_slug
    training_slug
  end

  # Sessions link back to the training interface only when the slot really
  # belongs to this training -- mentor and mentee surveys hang off shifts,
  # which have no session page.
  def session_url(slot)
    return unless slot && Training.session_position_ids(@training.id).include?(slot.position_id)

    training_session_path(training_slug, slot.id, year: @year)
  end
end
