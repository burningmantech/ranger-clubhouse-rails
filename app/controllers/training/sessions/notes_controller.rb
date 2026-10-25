# frozen_string_literal: true

# Trainer note edits and deletions from the score dialog. Only the note's
# author may touch it, and system audit rows (is_log) are immutable --
# server-enforced, not just hidden buttons.
class Training::Sessions::NotesController < Training::Sessions::BaseController
  before_action :load_note

  def edit
  end

  def update
    note = params.expect(trainee_note: [:note])[:note]

    if note.blank?
      return update_modal("training/sessions/notes/dialog",
                          { note: @note, error: "The note cannot be blank." })
    end

    @note.update!(note:)
    reopen_score_dialog("The note was updated.")
  end

  def destroy
    @note.destroy!
    reopen_score_dialog("The note was deleted.")
  end

  private

  def load_note
    @note = TraineeNote.find_by(id: params[:note_id], slot_id: @training_session.slot.id)

    if @note.nil?
      deny_note("The note no longer exists.")
    elsif @note.is_log || @note.person_source_id != Current.person.id
      deny_note("Only the trainer who wrote a note may change it.")
    end
  end

  def deny_note(message)
    render turbo_stream: [ui_toast_stream(message, :error), modal_close_dialog]
  end

  # Return to the trainee's score dialog with the notes list refreshed.
  def reopen_score_dialog(message)
    trainee = @training_session.trainee(@note.person_id)
    score_form = Training::ScoreForm.for(trainee)

    render turbo_stream: [
      turbo_stream.update("modal", partial: "training/sessions/scores/dialog",
                                   locals: { score_form:, trainee: }),
      ui_toast_stream(message, :success)
    ]
  end
end
