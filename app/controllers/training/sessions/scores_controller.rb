# frozen_string_literal: true

# The per-trainee score dialog: status, rank, notes, feedback delivered
# (Ember editStudent/saveStudent -> Laravel scoreStudent). Saves are
# per-trainee so two trainers scoring the same session cannot clobber each
# other.
class Training::Sessions::ScoresController < Training::Sessions::BaseController
  before_action :load_trainee

  def edit
    @score_form = Training::ScoreForm.for(@trainee)
  end

  def update
    @score_form = Training::ScoreForm.new(score_params)
    @score_form.trainee = @trainee

    unless @score_form.valid?
      return update_modal("training/sessions/scores/dialog",
                          { score_form: @score_form, trainee: @trainee })
    end

    @training_session.score!(@trainee.person.id, @score_form)

    render turbo_stream: [
      turbo_stream.update("trainees-section", partial: "training/sessions/trainees_section"),
      turbo_stream.update("session-stats", partial: "training/sessions/stats"),
      ui_toast_stream("#{@trainee.person.callsign}'s score saved.", :success),
      modal_close_dialog
    ]
  end

  private

  def load_trainee
    @trainee = @training_session.trainee(params[:person_id].to_i)
    return if @trainee

    render turbo_stream: [
      ui_toast_stream("That person is not signed up for this session.", :error),
      modal_close_dialog
    ]
  end

  def score_params
    scoped_params(:training_score_form, :status, :rank, :note, :feedback_delivered)
  end
end
