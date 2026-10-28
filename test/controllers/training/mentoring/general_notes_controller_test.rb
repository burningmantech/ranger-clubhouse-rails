# frozen_string_literal: true

require "test_helper"

# Training › Mentoring › Mentor Assignment: a general note's Edit and Delete,
# its author's alone, each redrawing the mentee's notes on the roster in place.
class Training::Mentoring::GeneralNotesControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include ArtMentoringTestHelper
  include PersonTestFactory

  SLUG = "green-dot"
  TRAINER_ROLE = Role::ART_TRAINER_BASE | Position::GREEN_DOT_TRAINING

  setup do
    Current.reset
    setup_art_mentoring
    ensure_role(TRAINER_ROLE, "Green Dot Interface")
    @trainer = person(:retired_ranger)
    grant_role(@trainer, TRAINER_ROLE)
    @mentee = create_person("Tinsel")
    @note = PersonMentoringNote.create!(person: @mentee, written_by: @trainer, notes: "Quiet on the radio.")
    sign_in_as(@trainer)
  end

  teardown { Current.reset }

  def note_path(note = @note) = training_mentoring_general_note_path(SLUG, note)

  def edit_note(notes) = patch(note_path, params: { person_mentoring_note: { notes: } }, as: :turbo_stream)

  test "the author edits a note in a dialog, and saving redraws the mentee's notes" do
    get edit_training_mentoring_general_note_path(SLUG, @note)

    assert_response :success
    assert_select "turbo-frame#modal dialog#general-note-dialog textarea[name=?]", "person_mentoring_note[notes]",
                  text: /Quiet on the radio\./

    edit_note("Calm on the radio.\r\nTwice.")

    assert_equal "Calm on the radio.\nTwice.", @note.reload.notes
    assert_turbo_stream action: "replace", target: "general-notes-#{@mentee.id}" do
      assert_select "template li", text: /Calm on the radio\.\s+Twice\./
    end
    assert_includes response.body, "General note updated."
    assert ActionLog.exists?(event: "person-mentoring-note-update"), "the edit is audited"
  end

  test "a blank note is refused in the dialog, and the note is kept" do
    edit_note("  ")

    assert_turbo_stream status: :unprocessable_entity, action: "update", target: "modal" do
      assert_select "template", text: /Note can't be blank\./
    end
    assert_equal "Quiet on the radio.", @note.reload.notes
  end

  test "the author deletes a note, and the mentee's notes are redrawn without it" do
    delete note_path, as: :turbo_stream

    assert_not PersonMentoringNote.exists?(@note.id)
    assert_turbo_stream action: "replace", target: "general-notes-#{@mentee.id}" do
      assert_select "template div#general-notes-#{@mentee.id}[hidden]"
    end
    assert_includes response.body, "General note deleted."
    assert ActionLog.exists?(event: "person-mentoring-note-delete"), "the deletion is audited"
  end

  test "another trainer can neither edit nor delete someone else's note" do
    other = create_person("Ferrous")
    grant_role(other, TRAINER_ROLE)
    sign_in_as(other)

    edit_note("Rewritten.")
    assert_includes response.body, "Only the person who wrote a general note can change it."
    delete note_path, as: :turbo_stream

    assert_equal "Quiet on the radio.", @note.reload.notes
  end

  test "an author without the trainer role cannot change their note" do
    outsider = create_person("Outsider")
    theirs = PersonMentoringNote.create!(person: @mentee, written_by: outsider, notes: "Theirs.")
    sign_in_as(outsider)

    delete note_path(theirs), as: :turbo_stream

    assert_response :redirect
    assert PersonMentoringNote.exists?(theirs.id)
  end
end
