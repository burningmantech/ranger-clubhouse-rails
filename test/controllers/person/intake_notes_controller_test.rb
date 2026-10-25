# frozen_string_literal: true

require "test_helper"

class Person::IntakeNotesControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include ActiveSupport::Testing::TimeHelpers

  NOT_AUTHORIZED = "Not authorized"

  setup do
    travel_to Time.zone.local(2026, 4, 16, 12, 0, 0)
    Rails.cache.clear
    Current.reset

    @target = person(:prospective_ranger)
    @other_target = person(:past_prospective_ranger)

    @admin = person(:auditor_ranger)              # personnel writer (no dedicated "personnel" role -- ADMIN only)
    @rrn_writer = person(:ranger_with_custom_gender)
    @vc_writer = person(:echelon_ranger)
    @mentor_writer = person(:retired_ranger)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::INTAKE, "Intake")
    ensure_role(Role::REGIONAL_MANAGEMENT, "Regional Management")
    ensure_role(Role::VC, "Volunteer Coordinator")
    ensure_role(Role::MENTOR, "Mentor")

    grant_role(@admin, Role::ADMIN)
    grant_role(@rrn_writer, Role::REGIONAL_MANAGEMENT)
    grant_role(@vc_writer, Role::VC)
    grant_role(@mentor_writer, Role::MENTOR)

    Current.person = @admin
  end

  teardown do
    Current.reset
    travel_back
    Rails.cache.clear
  end

  # --- per-team role gate on new/create -----------------------------------

  # A writer who legitimately holds a DIFFERENT team's role can reach this
  # controller (it's in the outer authorize_role list) but must still be
  # denied writing to a team they don't hold the role for -- and the same
  # writer's own team must still work, proving the block is per-type.
  test "new and create deny a writer lacking that specific team's role" do
    wrong_attempts = {
      "personnel" => @vc_writer,
      "rrn" => @vc_writer,
      "vc" => @rrn_writer,
      "mentor" => @rrn_writer
    }

    assert_no_difference -> { PersonIntakeNote.count } do
      wrong_attempts.each do |type, writer|
        sign_in_as(writer)

        get new_person_intake_note_path(@target, type: type)
        assert_redirected_to person_unified_flagging_path(@target), "new(#{type}) should have denied #{writer.callsign}"
        assert_equal NOT_AUTHORIZED, flash[:error]
        follow_redirect!

        post person_intake_notes_path(@target), params: {
          intake_note_form: { type: type, year: 2026, note: "Should not save.", ranking: "" }
        }
        assert_redirected_to person_unified_flagging_path(@target), "create(#{type}) should have denied #{writer.callsign}"
        assert_equal NOT_AUTHORIZED, flash[:error]
        follow_redirect!
      end
    end

    # Same writers, their own team's `new` still renders -- the denial above
    # was per-type, not a blanket lockout from the controller.
    sign_in_as(@vc_writer)
    get new_person_intake_note_path(@target, type: "vc")
    assert_response :success

    sign_in_as(@rrn_writer)
    get new_person_intake_note_path(@target, type: "rrn")
    assert_response :success
  end

  # --- create: note only ---------------------------------------------------

  test "a non-hash note param is refused on create and update rather than raising" do
    sign_in_as(@admin)

    assert_no_difference "PersonIntakeNote.count" do
      post person_intake_notes_path(@target), params: { intake_note_form: "x" }
    end
    assert_response :bad_request

    note = PersonIntakeNote.create!(person_source_id: @admin.id, person_id: @target.id, year: 2026,
                                    type: "personnel", note: "Original.")

    patch person_intake_note_path(@target, note), params: { person_intake_note: "x" }
    assert_response :bad_request
    assert_equal "Original.", note.reload.note
  end

  test "create with a note only appends a non-log note and leaves the rank untouched" do
    sign_in_as(@admin)
    intake = person_intake(:prospective_ranger_2023)

    # Intake notes are an audited model, so a create also writes an ActionLog row.
    assert_difference [-> { PersonIntakeNote.count }, -> { ActionLog.where(event: "person-intake-note-create").count }], 1 do
      post person_intake_notes_path(@target), params: {
        intake_note_form: { type: "personnel", year: 2023, note: "Follow-up call went well.", ranking: "" }
      }
    end

    assert_redirected_to person_unified_flagging_path(@target)
    note = PersonIntakeNote.order(:id).last
    assert_equal "personnel", note.type
    assert_equal "Follow-up call went well.", note.note
    assert_not note.is_log
    assert_equal @admin.id, note.person_source_id

    intake.reload
    assert_nil intake.personnel_rank
  end

  # --- create: ranking only -------------------------------------------------

  test "create with a ranking only, no prior rank, sets the rank and logs 'no rank -> N'" do
    sign_in_as(@mentor_writer)
    # 2025's fixture row only has vc_rank set; mentor_rank is nil going in.
    intake = person_intake(:prospective_ranger_2025)
    assert_nil intake.mentor_rank

    assert_difference -> { PersonIntakeNote.count }, 1 do
      post person_intake_notes_path(@target), params: {
        intake_note_form: { type: "mentor", year: 2025, note: "", ranking: "1" }
      }
    end

    assert_redirected_to person_unified_flagging_path(@target)

    intake.reload
    assert_equal 1, intake.mentor_rank
    assert_equal 3, intake.vc_rank, "sibling column for the same year must be untouched"

    log_note = PersonIntakeNote.order(:id).last
    assert log_note.is_log
    assert_equal "mentor", log_note.type
    assert_equal "rank change [no rank] -> [1]", log_note.note
    assert_equal @mentor_writer.id, log_note.person_source_id
  end

  test "create with a ranking that changes an existing rank logs 'old -> new'" do
    sign_in_as(@vc_writer)
    intake = person_intake(:prospective_ranger_2025)
    assert_equal 3, intake.vc_rank

    assert_difference -> { PersonIntakeNote.count }, 1 do
      post person_intake_notes_path(@target), params: {
        intake_note_form: { type: "vc", year: 2025, note: "", ranking: "1" }
      }
    end

    assert_redirected_to person_unified_flagging_path(@target)

    intake.reload
    assert_equal 1, intake.vc_rank

    log_note = PersonIntakeNote.order(:id).last
    assert log_note.is_log
    assert_equal "rank change [3] -> [1]", log_note.note
  end

  # Upstream quirk (mirrored deliberately, see app/forms/intake_note_form.rb):
  # a blank ranking selection can never clear an existing rank back to "no
  # rank" through this endpoint. With no note either, there is nothing to
  # save, so the stricter Rails-side validation rejects it outright.
  test "create cannot clear an existing rank to 'no rank' via a blank ranking" do
    sign_in_as(@rrn_writer)
    intake = person_intake(:prospective_ranger_2024)
    assert_equal 2, intake.rrn_rank

    assert_no_difference -> { PersonIntakeNote.count } do
      post person_intake_notes_path(@target), params: {
        intake_note_form: { type: "rrn", year: 2024, note: "", ranking: "" }
      }
    end

    assert_response :unprocessable_entity
    assert_select "body", text: /Please select a rank and\/or enter a note/
    assert_equal 2, intake.reload.rrn_rank
  end

  # --- new: ranking dropdown reflects the current rank ----------------------

  # Matches the Ember modal, which opens with the team's existing rank pre-selected
  # rather than always on "No Ranking".
  test "new pre-selects the team's current rank in the ranking dropdown" do
    sign_in_as(@admin)
    assert_equal 4, person_intake(:prospective_ranger_2026).personnel_rank

    get new_person_intake_note_path(@target, type: "personnel", year: 2026)

    assert_response :success
    assert_select "select[name=?]", "intake_note_form[ranking]" do
      assert_select "option[selected][value=?]", "4"
    end
  end

  # --- create: ranking outside the valid 1-4 range --------------------------

  # The select only offers "" or 1-4, but a hand-crafted POST could carry any
  # integer; an out-of-range rank must be rejected, never persisted.
  test "create rejects a ranking outside the valid range" do
    sign_in_as(@admin)

    assert_no_difference [-> { PersonIntakeNote.count }, -> { PersonIntake.count }] do
      post person_intake_notes_path(@target), params: {
        intake_note_form: { type: "personnel", year: 2023, note: "", ranking: "99" }
      }
    end

    assert_response :unprocessable_entity
  end

  # --- create: neither note nor an actual rank change -----------------------

  test "create is rejected when neither a note nor an actual rank change is present" do
    sign_in_as(@admin)

    [
      { note: "", ranking: "" },                # nothing at all
      { note: "", ranking: "4" }                # ranking resubmitted unchanged (2026 personnel_rank is already 4)
    ].each do |attrs|
      assert_no_difference [-> { PersonIntakeNote.count }, -> { PersonIntake.count }] do
        post person_intake_notes_path(@target), params: {
          intake_note_form: { type: "personnel", year: 2026, **attrs }
        }
      end

      assert_response :unprocessable_entity
      assert_select "body", text: /Please select a rank and\/or enter a note/
    end
  end

  # --- edit / update ---------------------------------------------------------

  test "edit and update refuse a log note" do
    sign_in_as(@admin)
    note = person_intake_note(:prospective_personnel_rank_change_2026)

    get edit_person_intake_note_path(@target, note)
    assert_redirected_to person_unified_flagging_path(@target)
    assert_equal "Cannot update a log note.", flash[:error]
    follow_redirect!

    patch person_intake_note_path(@target, note), params: { person_intake_note: { note: "hacked" } }
    assert_redirected_to person_unified_flagging_path(@target)
    assert_equal "Cannot update a log note.", flash[:error]

    assert_equal "rank change [no rank] -> [4]", note.reload.note
  end

  test "edit and update succeed for a non-log note by the correct role" do
    sign_in_as(@admin)
    note = person_intake_note(:prospective_personnel_note_2026_a)

    get edit_person_intake_note_path(@target, note)
    assert_response :success

    patch person_intake_note_path(@target, note), params: { person_intake_note: { note: "Corrected the note text." } }

    assert_redirected_to person_unified_flagging_path(@target)
    assert_equal "Corrected the note text.", note.reload.note
  end

  test "update is denied for a writer lacking that team's role" do
    sign_in_as(@vc_writer)
    note = person_intake_note(:prospective_personnel_note_2026_a)

    patch person_intake_note_path(@target, note), params: { person_intake_note: { note: "hacked" } }

    assert_redirected_to person_unified_flagging_path(@target)
    assert_equal NOT_AUTHORIZED, flash[:error]
    assert_not_equal "hacked", note.reload.note
  end

  # --- destroy ----------------------------------------------------------------

  test "destroy refuses a log note even for the correct role" do
    sign_in_as(@admin)
    note = person_intake_note(:prospective_personnel_rank_change_2026)

    delete person_intake_note_path(@target, note)

    assert_redirected_to person_unified_flagging_path(@target)
    assert_equal "Not authorized to delete note.", flash[:error]
    assert PersonIntakeNote.exists?(note.id)
  end

  test "destroy succeeds for a non-log note by the correct role" do
    sign_in_as(@admin)
    note = person_intake_note(:prospective_personnel_note_2026_b)

    assert_difference -> { PersonIntakeNote.count }, -1 do
      delete person_intake_note_path(@target, note)
    end

    assert_redirected_to person_unified_flagging_path(@target)
    assert_equal "Note deleted.", flash[:success]
    assert_not PersonIntakeNote.exists?(note.id)
  end

  test "destroy is denied for a writer lacking that team's role" do
    sign_in_as(@vc_writer)
    note = person_intake_note(:prospective_personnel_note_2026_b)

    delete person_intake_note_path(@target, note)

    assert_redirected_to person_unified_flagging_path(@target)
    assert_equal NOT_AUTHORIZED, flash[:error]
    assert PersonIntakeNote.exists?(note.id)
  end

  # --- origin round trip ---------------------------------------------------
  #
  # Notes are reachable from two pages. Without the origin token, saving from
  # the VC pipeline page's pane dumps the writer on the person page instead of
  # back where they were working. The pipeline page selects the person again
  # from ?person= -- an anchor would be dropped after the form's submission.

  test "create from the VC pipeline page returns there with the person selected" do
    sign_in_as(@admin)

    post person_intake_notes_path(@target, origin: "vc", origin_year: 2026), params: {
      intake_note_form: { type: "personnel", year: 2026, note: "Saved from the pipeline page.", ranking: "" }
    }

    assert_redirected_to vc_unified_flagging_path(year: 2026, person: @target.id)
    assert_equal "Note saved.", flash[:success]
  end

  test "destroy from the VC pipeline page returns there" do
    sign_in_as(@admin)
    note = person_intake_note(:prospective_personnel_note_2026_b)

    delete person_intake_note_path(@target, note, origin: "vc", origin_year: 2025)

    assert_redirected_to vc_unified_flagging_path(year: 2025, person: @target.id)
  end

  test "an unrecognized origin falls back to the person page" do
    sign_in_as(@admin)

    post person_intake_notes_path(@target, origin: "https://evil.example.com"), params: {
      intake_note_form: { type: "personnel", year: 2026, note: "Origin should be ignored.", ranking: "" }
    }

    assert_redirected_to person_unified_flagging_path(@target)
  end

  # A note that belongs to a DIFFERENT person than the URL's :person_id must
  # 404, not silently no-op or -- worse -- act on the wrong PNV's record.
  test "a note belonging to a different person cannot be reached through this person's URL" do
    sign_in_as(@admin)
    other_note = person_intake_note(:past_prospective_personnel_note_2026)
    assert_equal @other_target.id, other_note.person_id

    begin
      delete person_intake_note_path(@target, other_note)
      assert_response :not_found
    rescue ActiveRecord::RecordNotFound
      # Expected behavior when RecordNotFound propagates instead of being rescued into a response.
    end

    assert PersonIntakeNote.exists?(other_note.id)

    begin
      get edit_person_intake_note_path(@target, other_note)
      assert_response :not_found
    rescue ActiveRecord::RecordNotFound
      # Expected behavior when RecordNotFound propagates instead of being rescued into a response.
    end
  end

  private

  def ensure_role(id, title)
    role = Role.find_or_initialize_by(id: id)
    role.title = title
    role.new_user_eligible = false
    role.save!
  end

  def grant_role(person, role_id)
    PersonRole.find_or_create_by!(person_id: person.id, role_id: role_id)
    RoleManager.purge_person(person.id.to_s)
  end
end
