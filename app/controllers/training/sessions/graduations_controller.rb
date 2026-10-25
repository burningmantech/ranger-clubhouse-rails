# frozen_string_literal: true

# The ART graduation dialog: eligibility buckets on GET, the grant on POST
# (Laravel graduationCandidates / graduateCandidates). Gated on the ART's
# composed graduate role rather than the trainer role.
class Training::Sessions::GraduationsController < Training::Sessions::BaseController
  skip_before_action :authorize_session_management
  before_action :authorize_graduation
  before_action :load_graduation

  def show
  end

  def create
    ids = IdList.parse(params[:person_ids])

    if ids.empty?
      return update_modal("training/sessions/graduations/dialog",
                          { graduation: @graduation, error: "Pick at least one trainee to graduate." })
    end

    @results = @graduation.graduate!(ids)
    granted = @results.count { |result| result.status == "success" }

    render turbo_stream: [
      turbo_stream.update("modal", partial: "training/sessions/graduations/results",
                                   locals: { graduation: @graduation, results: @results }),
      ui_toast_stream("#{granted} #{"trainee".pluralize(granted)} graduated.",
                      granted.positive? ? :success : :warning)
    ]
  end

  private

  def load_graduation
    @graduation = TrainingSession::Graduation.new(@training_session)
    return if @graduation.offered?

    redirect_to session_return_path, error: "#{@training.title} has no positions to graduate to."
  end
end
