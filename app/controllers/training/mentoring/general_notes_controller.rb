# frozen_string_literal: true

# A general note's Edit and Delete on the Mentor Assignment roster
# (PersonMentoringNote). Only its author may change it, and only while holding
# the ART's trainer role a roster's Save needs (chosen by Claude 2026-10-28,
# reversible: a training session's notes are their author's alone too). Each
# answers with a stream that redraws the mentee's notes in place, so a roster
# being filled in keeps what was typed into it.
class Training::Mentoring::GeneralNotesController < Training::Mentoring::BaseController
  skip_before_action :load_shifts
  before_action :authorize_session_management
  before_action :load_note

  def edit; end

  def update
    @note.notes = ArtMentoring::Assignment.clean(params.expect(person_mentoring_note: [:notes])[:notes])
    return redraw_notes("General note updated.") if @note.save

    render turbo_stream: turbo_stream.update("modal", partial: "training/mentoring/general_notes/dialog",
                                                      locals: { note: @note }),
           status: :unprocessable_entity
  end

  def destroy
    @note.destroy!
    redraw_notes("General note deleted.")
  end

  private

  def load_note
    @note = PersonMentoringNote.find_by(id: params[:id])

    if @note.nil?
      deny_note("That general note no longer exists.")
    elsif !@note.written_by?(Current.person)
      deny_note("Only the person who wrote a general note can change it.")
    end
  end

  def deny_note(message)
    render turbo_stream: [ui_toast_stream(message, :error), modal_close_dialog]
  end

  def redraw_notes(message)
    person = @note.person
    render turbo_stream: [
      turbo_stream.replace("general-notes-#{person.id}", partial: "training/mentoring/assignments/general_notes_list",
                                                        locals: { notes: PersonMentoringNote.for_people([person.id]),
                                                                  person_id: person.id, callsign: person.callsign }),
      modal_close_dialog,
      ui_toast_stream(message, :success)
    ]
  end
end
