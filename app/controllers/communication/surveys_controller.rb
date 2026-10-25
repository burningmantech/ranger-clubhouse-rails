# frozen_string_literal: true

# The feedback surveys shown on the Clubhouse dashboard: who answers each one,
# what it says, and whether it is switched on. The groups and questions inside
# a survey have controllers of their own.
#
# Reading the answers is somewhere else entirely -- a training's own Surveys
# page, or the Mentors' Alpha Surveys -- and this page links to it.
#
# Two departures from the page this replaces:
#
#   * A duplicate starts switched off. Copying the original's setting put a
#     half-edited survey on people's dashboards the moment it was made.
#   * The position offered for a survey is one the person manages, and the
#     kind of survey has to match the kind of position. The page it replaces
#     offered every mentor and mentee position to anyone who could see the
#     form, and the save was refused afterwards with no explanation.
class Communication::SurveysController < Communication::SurveyManagementBaseController
  before_action :setup_year, only: [:index, :new, :create]
  before_action :load_survey, only: [:show, :edit, :update, :destroy, :duplicate]
  # After the survey is loaded, so an edit no one is allowed is turned away
  # before the form's choices are worked out. A save that succeeds redirects,
  # so create and update ask for them only when they have a form to re-render.
  before_action :load_form_options, only: [:new, :edit]

  def index
    # Already narrowed to the surveys this person manages, with the answered
    # flag set for the whole list in one query.
    @surveys = Survey.find_for_query(year: @year)
    # Worked out only when there is nothing to show, and only to explain the
    # nothing: a survey permission can name a position the Clubhouse does not
    # yet map to surveys, and then this page can do nothing for the reader.
    @manages_no_positions = @surveys.empty? && Survey.manages_no_positions?(Current.person)
    # Only this list says what a mentoring survey asks about, so it is
    # preloaded here rather than by the finder the report pages share.
    ActiveRecord::Associations::Preloader.new(records: @surveys, associations: :mentoring_position).call
  end

  def show
    @groups = @survey.survey_groups.includes(:survey_questions).to_a
    @question_count = @groups.sum { |group| group.survey_questions.size }
    # An edit sends the reader back here naming the group they were working
    # on, and the page scrolls to it. A group id from anywhere else is
    # ignored rather than scrolled to nothing.
    @focus_group_id = @groups.map(&:id).find { |id| id == params[:group].to_s.to_i }
  end

  def new
    @survey = Survey.new(year: @year, type: @type_options.first)
  end

  def create
    @survey = Survey.new(survey_params)
    @survey.year = @year
    # A survey is switched on from its own page, once it has questions to
    # ask. The form that makes one does not offer the setting.
    @survey.active = false

    unless save_survey
      load_form_options
      return render(:new, status: :unprocessable_entity)
    end

    redirect_to communication_survey_path(@survey),
                success: "Survey created. Add its first group of questions."
  end

  def edit
  end

  def update
    @survey.assign_attributes(survey_params)

    unless save_survey
      load_form_options
      return render(:edit, status: :unprocessable_entity)
    end

    redirect_to communication_survey_path(@survey), success: "Survey updated."
  end

  def destroy
    year = @survey.year
    title = @survey.title
    @survey.destroy!

    redirect_to communication_surveys_path(year:), success: "\"#{title}\" deleted."
  end

  # Last year's survey, copied into this one to be edited rather than rebuilt.
  # A copy that would collide with a survey this year already has is refused
  # by the survey itself, and the message says so.
  def duplicate
    copy = @survey.duplicate_into(current_year)

    redirect_to communication_survey_path(copy),
                success: "Survey copied to #{current_year}. It stays switched off until you activate it."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to communication_survey_path(@survey),
                error: "The survey could not be copied: #{e.record.errors.full_messages.join(" ")}"
  end

  private

  # A survey's own pages name it in the path as :id.
  def survey_id_param
    params[:id]
  end

  # The choices the survey form offers. The kinds and the positions are worked
  # out from what this person manages, so the form cannot offer a survey they
  # would then be refused; what a mentoring survey asks about is not narrowed
  # that way, because it names who is being rated.
  def load_form_options
    @manageable_positions, every_position = Survey.form_positions(Current.person)
    @type_options = Survey.type_options_for(Current.person, @manageable_positions)
    @mentoring_positions = every_position.slice(:mentor, :mentee)
  end

  # Saving is refused when the position is not one this person manages --
  # otherwise they could hand themselves a survey they cannot open, or take
  # someone else's survey out of their hands.
  def save_survey
    unless @survey.can_manage_survey?(Current.person)
      @survey.errors.add(:position_id, "Position must be one you manage surveys for")
      return false
    end

    @survey.save
  end

  def survey_params
    params.expect(survey: [:type, :position_id, :mentoring_position_id, :title,
                           :prologue, :epilogue, :active])
  end
end
