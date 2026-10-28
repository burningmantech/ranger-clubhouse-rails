# frozen_string_literal: true

require "test_helper"

# Training › Mentoring › Mentor Assignment: the picker, one shift's roster and
# its save, a shift still to come, and a past year's roster, recorded like the current one.
class Training::Mentoring::AssignmentsControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include ArtMentoringTestHelper
  include PersonTestFactory
  include DomIdTestHelper
  include ActiveSupport::Testing::TimeHelpers

  YEAR = 2026
  SLUG = "green-dot"

  setup do
    travel_to Time.zone.local(YEAR, 9, 2, 19, 0, 0)
    Rails.cache.clear
    Current.reset
    setup_art_mentoring

    ensure_role(Role::TRAINER, "Trainer")
    ensure_role(Role::ART_TRAINER_BASE | Position::GREEN_DOT_TRAINING, "Green Dot Interface")
    @art_trainer = person(:retired_ranger)
    @dirt_trainer = person(:echelon_ranger)
    grant_role(@art_trainer, Role::ART_TRAINER_BASE | Position::GREEN_DOT_TRAINING)
    grant_role(@dirt_trainer, Role::TRAINER)

    @slot = mentee_shift(Time.zone.local(YEAR, 9, 1, 17, 45, 0))
    @ferrous = create_person("Ferrous")
    @cinder = create_person("Cinder")
    hold_mentor_position(@ferrous, @cinder)
    mentor_entry(@ferrous, @slot.begins - 10.minutes, off_duty: @slot.ends)
    @tinsel = mentee_entry(create_person("Tinsel"), @slot.begins, off_duty: @slot.ends, slot: @slot)

    sign_in_as(@art_trainer)
  end

  teardown do
    Current.reset
    Rails.cache.clear
    travel_back
  end

  def shift_path(key = @slot.id, year: YEAR) = training_mentoring_assignment_shift_path(SLUG, key, year:)

  # One row as the roster posts it: every mentor slot, each [id, notes, the
  # mentor the slot showed when drawn], the ones not given left blank; and,
  # when given, the walk's fingerprint as drawn.
  def walk_params(*slots, status: PersonMentor::STATUS_PENDING, was: nil)
    mentors = Array.new(ArtMentoring::Assignment::MENTOR_SLOTS) do |i|
      id, notes, loaded_id = slots[i]
      [i.to_s, { id: id.to_s, notes: notes.to_s, loaded_id: loaded_id.to_s }]
    end
    { status:, mentors: mentors.to_h, was: }.compact
  end

  # The fingerprint the last page drew into an entry's row.
  def drawn_was(entry = @tinsel) = css_select("input[name='walks[#{entry.id}][was]']").first["value"]

  def save_walk(mentor_id:, status: PersonMentor::STATUS_PENDING, notes: "", entry: @tinsel, path: shift_path,
                general_notes: {})
    post path, params: { walks: { entry.id => walk_params([mentor_id, notes], status:) }, general_notes: }
  end

  test "the picker shows each mentoring shift as a card that opens its roster" do
    get training_mentoring_assignment_path(SLUG)

    assert_response :success
    assert_select "a[href=?]", shift_path, text: /Manage/
    assert_includes response.body, "1 need a mentor", "the shift has ended, and no one was paired with Tinsel"
    assert_not_includes response.body, "awaiting a verdict", "a verdict waits on a mentor"
  end

  test "a picker card names each mentee once, by callsign, with their sign-ins when there are more" do
    mentee_entry(@tinsel.person, @slot.begins + 30.minutes, off_duty: @slot.ends, slot: @slot)
    mentee_entry(create_person("Aster"), @slot.begins + 5.minutes, off_duty: @slot.ends, slot: @slot)

    get training_mentoring_assignment_path(SLUG)

    assert_includes response.body, "Mentees: Aster and Tinsel (2 sign-ins)."
    assert_includes response.body, "3 mentees", "the badge beside it counts sign-ins"
  end

  test "a shift's roster offers the mentors on shift before everyone else holding the position" do
    get shift_path

    assert_response :success
    select = "select#walk-#{@tinsel.id}-mentor-1"
    assert_select "#{select} optgroup[label=?] option", "On shift", text: /\AFerrous · signed in/
    assert_select "#{select} optgroup[label=?] option", "Other mentors", text: "Cinder"
    ArtMentoring::Assignment::MENTOR_SLOTS.times do |i|
      assert_select "select[name=?]", "walks[#{@tinsel.id}][mentors][#{i}][id]", count: 1
      assert_select "textarea[name=?]", "walks[#{@tinsel.id}][mentors][#{i}][notes]", count: 1
      assert_select "input[type=hidden][name=?]", "walks[#{@tinsel.id}][mentors][#{i}][loaded_id]", count: 1
    end
    assert_select "select[id^=?]", "walk-#{@tinsel.id}-mentor-", count: ArtMentoring::Assignment::MENTOR_SLOTS
    assert_select "input[type=hidden][name=?]", "walks[#{@tinsel.id}][was]", count: 1
    assert_select "form[action=?]", shift_path
  end

  test "the roster renders no duplicate DOM ids with a mentee signed in twice" do
    mentee_entry(@tinsel.person, @slot.begins + 30.minutes, off_duty: @slot.ends, slot: @slot)

    get shift_path

    assert_response :success
    assert_unique_dom_ids
    assert_select "textarea[name=?]", "general_notes[#{@tinsel.person_id}]", count: 1
  end

  test "a mentee holding the mentor position is not offered as their own mentor" do
    hold_mentor_position(@tinsel.person)

    get shift_path

    assert_select "select#walk-#{@tinsel.id}-mentor-1 option[value=?]", @tinsel.person_id.to_s, count: 0
    assert_select "select#walk-#{@tinsel.id}-mentor-1 option", text: "Cinder"
  end

  test "a note keeps an emoji, and a line break counts once against its limit" do
    note = "Great walk 👍\r\n#{"a" * (ArtMentoring::Assignment::NOTES_MAX - 13)}"

    save_walk(mentor_id: @ferrous.id, notes: note)

    assert_redirected_to shift_path
    assert_equal note.sub("\r\n", "\n"), PersonMentor.find_by!(timesheet_id: @tinsel.id).notes
  end

  test "a roster for sign-ins matching no shift names the hour from its first sign-in" do
    loose = mentee_entry(create_person("Moonrake"), Time.zone.local(YEAR, 9, 2, 3, 10, 0),
                         off_duty: Time.zone.local(YEAR, 9, 2, 6, 0, 0), loose: true)

    get shift_path("t#{loose.id}")

    assert_response :success
    assert_match(/signed in between.*03:10.* and .*04:10.* are listed/m, response.body)
    assert_no_match(/02:10/, response.body)
  end

  test "saving the roster records the pairing and returns to the shift" do
    save_walk(mentor_id: @ferrous.id, status: PersonMentor::STATUS_PASS, notes: "Ready.")

    assert_redirected_to shift_path
    assert_equal "Recorded 1 mentee.", flash[:success]
    walk = PersonMentor.find_by!(timesheet_id: @tinsel.id)
    assert_equal [@ferrous.id, PersonMentor::STATUS_PASS, "Ready."], [walk.mentor_id, walk.status, walk.notes]
  end

  test "two mentors are recorded with their own notes, and the roster shows each in its slot" do
    post shift_path, params: { walks: { @tinsel.id => walk_params([@ferrous.id, "Ready."],
                                                                  [@cinder.id, "Calm on the radio."]) } }

    assert_redirected_to shift_path
    assert_equal({ @ferrous.id => "Ready.", @cinder.id => "Calm on the radio." },
                 PersonMentor.where(timesheet_id: @tinsel.id).pluck(:mentor_id, :notes).to_h)

    get shift_path
    assert_select "select#walk-#{@tinsel.id}-mentor-1 option[selected][value=?]", @ferrous.id.to_s
    assert_select "select#walk-#{@tinsel.id}-mentor-2 option[selected][value=?]", @cinder.id.to_s
    assert_select "select#walk-#{@tinsel.id}-mentor-3 option[selected]:not([value=''])", count: 0
    assert_select "textarea#walk-#{@tinsel.id}-mentor-1-notes", text: /Ready\./
    assert_select "textarea#walk-#{@tinsel.id}-mentor-2-notes", text: /Calm on the radio\./
    assert_select "label[for=?]", "walk-#{@tinsel.id}-mentor-2-notes", text: "Mentor 2 Notes"
  end

  # The shape a roster drawn before per-mentor notes posts.
  test "a row posted without its mentor slots is refused and shows what is saved, so a second Save clears nothing" do
    walk(@tinsel, @ferrous, notes: "Ready.")

    post shift_path, params: { walks: { @tinsel.id => { status: PersonMentor::STATUS_PENDING, mentor_ids: [""],
                                                        notes: "An older page." } } }

    assert_response :unprocessable_entity
    assert_select "tr#walk-#{@tinsel.id}-error", text: /This row could not be read, so it shows what is saved now\./
    assert_select "select#walk-#{@tinsel.id}-mentor-1 option[selected][value=?]", @ferrous.id.to_s
    assert_select "textarea#walk-#{@tinsel.id}-mentor-1-notes", text: /Ready\./
    assert PersonMentor.exists?(timesheet_id: @tinsel.id, mentor_id: @ferrous.id)
  end

  test "mentor slots in any shape but the form's are refused, never read as a clear" do
    walk(@tinsel, @ferrous)
    shapes = [{ "0" => @cinder.id.to_s },                                   # a slot that is a bare value
              { "x" => { id: @cinder.id.to_s } },                          # a slot keyed by a word
              { id: @cinder.id.to_s },                                     # a slot's fields with no slot
              { "0" => { id: @ferrous.id.to_s }, "1" => @cinder.id.to_s }, # a slot beside a bare value
              { "0" => { id: [@cinder.id.to_s] } }]                        # a list where an id goes

    shapes.each do |mentors|
      post shift_path, params: { walks: { @tinsel.id => { status: PersonMentor::STATUS_PENDING, mentors: } } }

      assert_response :unprocessable_entity, mentors.inspect
      assert_select "tr#walk-#{@tinsel.id}-error", text: /This row could not be read/
    end
    assert_equal [@ferrous.id], PersonMentor.where(timesheet_id: @tinsel.id).pluck(:mentor_id)
  end

  test "a row someone else saved after the page was drawn is refused and shows what they saved" do
    get shift_path
    was = drawn_was
    walk(@tinsel, @ferrous, notes: "Ready.") # saved by someone else meanwhile

    post shift_path, params: { walks: { @tinsel.id => walk_params([@cinder.id, "Calm on the radio."], was:) } }

    assert_response :unprocessable_entity
    assert_select "tr#walk-#{@tinsel.id}-error", text: /Someone else saved this mentee after you opened the page/
    assert_select "select#walk-#{@tinsel.id}-mentor-1 option[selected][value=?]", @ferrous.id.to_s
    assert_select "textarea#walk-#{@tinsel.id}-mentor-1-notes", text: /Ready\./
    assert_equal [@ferrous.id], PersonMentor.where(timesheet_id: @tinsel.id).pluck(:mentor_id)
  end

  test "a row left as drawn keeps what someone else saved since" do
    get shift_path
    was = drawn_was
    walk(@tinsel, @ferrous, notes: "Ready.")

    post shift_path, params: { walks: { @tinsel.id => walk_params(was:) },
                               general_notes: { @tinsel.person_id => "Ask about the radio." } }

    assert_redirected_to shift_path
    assert_equal "General note added.", flash[:success]
    assert_equal [[@ferrous.id, "Ready."]], PersonMentor.where(timesheet_id: @tinsel.id).pluck(:mentor_id, :notes)
  end

  test "a slot changed to another mentor asks once before the notes in its box go with them" do
    walk(@tinsel, @ferrous, notes: "Ready.")
    get shift_path
    assert_select "input[name=?][value=?]", "walks[#{@tinsel.id}][mentors][0][loaded_id]", @ferrous.id.to_s

    post shift_path, params: { walks: { @tinsel.id => walk_params([@cinder.id, "Ready.", @ferrous.id], was: drawn_was) } }

    assert_response :unprocessable_entity
    assert_select "tr#walk-#{@tinsel.id}-error", text: /Mentor 1 changed from Ferrous to Cinder, but its notes are Ferrous's\./
    assert_select "select#walk-#{@tinsel.id}-mentor-1 option[selected][value=?]", @cinder.id.to_s
    assert_select "input[name=?][value=?]", "walks[#{@tinsel.id}][mentors][0][loaded_id]", @cinder.id.to_s
    assert_equal [@ferrous.id], PersonMentor.where(timesheet_id: @tinsel.id).pluck(:mentor_id)

    post shift_path, params: { walks: { @tinsel.id => walk_params([@cinder.id, "Ready.", @cinder.id], was: drawn_was) } }

    assert_redirected_to shift_path
    assert_equal [[@cinder.id, "Ready."]], PersonMentor.where(timesheet_id: @tinsel.id).pluck(:mentor_id, :notes)
  end

  test "Mentees' Other Shifts prints each mentor's notes on a line of its own" do
    later = mentee_shift(@slot.begins + 1.day)
    again = mentee_entry(@tinsel.person, later.begins, off_duty: later.ends, slot: later)
    walk(again, @ferrous, notes: "Ready.")
    walk(again, @cinder, notes: "Calm on the radio.")

    get shift_path

    assert_select "div.whitespace-pre-line", text: "Ferrous: Ready."
    assert_select "div.whitespace-pre-line", text: "Cinder: Calm on the radio."
  end

  # ------------------------------------------------------------ general notes

  test "the roster lists the general notes about a mentee from every year, newest first" do
    PersonMentoringNote.create!(person: @tinsel.person, written_by: @cinder, notes: "Quiet on the radio.",
                                created_at: Time.zone.local(YEAR - 2, 9, 1, 12, 0, 0))
    PersonMentoringNote.create!(person: @tinsel.person, written_by: @ferrous, notes: "Much better this year.")

    get shift_path

    assert_select "tr#walk-#{@tinsel.id}-general-notes-row" do
      assert_select "li", count: 2
      assert_select "li:first-child", text: /Sep 2, 2026 @ \d\d:\d\d · Ferrous.*Much better this year\./m
      assert_select "li:last-child", text: /Sep 1, 2024 @ \d\d:\d\d · Cinder.*Quiet on the radio\./m
      assert_select "textarea[name=?][aria-label=?]", "general_notes[#{@tinsel.person_id}]", "Add a general note about Tinsel"
      assert_select "p#general-note-#{@tinsel.person_id}-help",
                    text: "Saved with the shift, and shown on every roster this mentee is on, in any ART and any year."
      assert_select "a", count: 0, message: "only a note's author gets Edit and Delete"
    end
  end

  test "the reader's own general notes have Edit and Delete" do
    mine = PersonMentoringNote.create!(person: @tinsel.person, written_by: @art_trainer, notes: "Mine.")
    PersonMentoringNote.create!(person: @tinsel.person, written_by: @cinder, notes: "Theirs.")

    get shift_path

    assert_select "#general-notes-#{@tinsel.person_id}" do
      assert_select "a", count: 2
      assert_select "a[href=?][data-turbo-frame=modal]", edit_training_mentoring_general_note_path(SLUG, mine)
      assert_select "a[href=?][data-turbo-method=delete]", training_mentoring_general_note_path(SLUG, mine)
    end
  end

  test "a save adds a general note by its author, and says so" do
    save_walk(mentor_id: @ferrous.id, general_notes: { @tinsel.person_id => "Ask about the radio.\r\nTwice." })

    assert_redirected_to shift_path
    assert_equal "Recorded 1 mentee. General note added.", flash[:success]
    note = PersonMentoringNote.find_by!(person_id: @tinsel.person_id)
    assert_equal ["Ask about the radio.\nTwice.", @art_trainer.id], [note.notes, note.written_by_id]
    assert ActionLog.exists?(event: "person-mentoring-note-create"), "the note is audited"
  end

  test "a refused save keeps the typed general note and writes nothing" do
    save_walk(mentor_id: "", status: PersonMentor::STATUS_BONK,
              general_notes: { @tinsel.person_id => "Ask about the radio." })

    assert_response :unprocessable_entity
    assert_select "textarea#general-note-#{@tinsel.person_id}", text: /Ask about the radio\./
    assert_not PersonMentoringNote.exists?(person_id: @tinsel.person_id)
  end

  test "the result select offers the two ART-only verdicts, and a save records one" do
    get shift_path

    assert_select "select#walk-#{@tinsel.id}-status option", count: PersonMentor::STATUSES.size
    assert_select "select#walk-#{@tinsel.id}-status option[value=?]", PersonMentor::STATUS_ABSTAIN, text: "Abstained"

    save_walk(mentor_id: @ferrous.id, status: PersonMentor::STATUS_NOT_COMPLETED)

    assert_redirected_to shift_path
    assert_equal PersonMentor::STATUS_NOT_COMPLETED, PersonMentor.find_by!(timesheet_id: @tinsel.id).status
  end

  test "a refused row comes back at 422 with its reason and what was typed" do
    save_walk(mentor_id: "", status: PersonMentor::STATUS_BONK)

    assert_response :unprocessable_entity
    assert_includes response.body, "Pick a mentor before recording a result."
    assert_select "select#walk-#{@tinsel.id}-status option[selected][value=?]", PersonMentor::STATUS_BONK
    # The reason sits right under the fields it is about, and the general notes
    # below it are not shaded as though they had failed.
    assert_select "tr#walk-#{@tinsel.id}-notes-row + tr#walk-#{@tinsel.id}-error + " \
                  "tr#walk-#{@tinsel.id}-general-notes-row:not([class*=bg-error])"
    assert_not PersonMentor.exists?(timesheet_id: @tinsel.id)
  end

  test "a past year's roster is recorded like the current one" do
    old_slot = mentee_shift(Time.zone.local(YEAR - 1, 8, 31, 17, 45, 0))
    old = mentee_entry(create_person("Quartz"), old_slot.begins, off_duty: old_slot.ends, slot: old_slot)
    old_path = shift_path(old_slot.id, year: YEAR - 1)

    get old_path

    assert_response :success
    assert_not_includes response.body, "#{YEAR - 1} is over"
    assert_select "form[action=?]", old_path
    assert_select "select#walk-#{old.id}-mentor-1:not([disabled])"

    save_walk(mentor_id: @ferrous.id, entry: old, path: old_path)

    assert_redirected_to old_path
    walk = PersonMentor.find_by(timesheet_id: old.id)
    assert_equal [@ferrous.id, YEAR - 1], [walk.mentor_id, walk.mentor_year]
  end

  test "a shift still to come shows its sign-ups and takes no save" do
    future = mentee_shift(Time.zone.local(YEAR, 9, 3, 5, 45, 0))
    sign_up(create_person("Paprika"), future)

    get shift_path(future.id)

    assert_response :success
    assert_includes response.body, "Paprika"
    assert_includes response.body, "No one has signed up to mentor this shift yet."

    save_walk(mentor_id: @ferrous.id, path: shift_path(future.id))

    assert_redirected_to shift_path(future.id)
    assert_equal "No one has signed in for that shift yet, so there is nothing to record.", flash[:error]
  end

  test "an unknown shift goes back to the picker" do
    get shift_path(999_999)

    assert_redirected_to training_mentoring_assignment_path(SLUG, year: YEAR)
  end

  test "an In-Person trainer cannot save an ART's roster" do
    sign_in_as(@dirt_trainer)

    save_walk(mentor_id: @ferrous.id)

    assert_redirected_to me_root_path
    assert_not PersonMentor.exists?(timesheet_id: @tinsel.id)
  end

  # ------------------------------------------------------------ passing

  def become_graduate
    ensure_role(Role::ART_GRADUATE_BASE | Position::GREEN_DOT_TRAINING, "Green Dot Graduate")
    grant_role(@art_trainer, Role::ART_GRADUATE_BASE | Position::GREEN_DOT_TRAINING)
  end

  def answer_pass(join: "1", revoke: "1")
    post shift_path, params: { walks: { @tinsel.id => walk_params([@ferrous.id], status: PersonMentor::STATUS_PASS) },
                               confirmed: "Record Pass",
                               grants: { @tinsel.id => { join:, revoke: } } }
  end

  test "a graduate passing someone is asked first, and nothing is written yet" do
    become_graduate
    recommended_position("Dirt - Green Dot")
    hold_mentee_position(@tinsel.person)

    save_walk(mentor_id: @ferrous.id, status: PersonMentor::STATUS_PASS)

    assert_response :unprocessable_entity
    assert_select "dialog#pass-dialog", text: /Pass Tinsel/ do
      assert_select "input[type=checkbox][name=?][checked]", "grants[#{@tinsel.id}][join]"
      assert_select "input[type=checkbox][name=?][checked]", "grants[#{@tinsel.id}][revoke]"
      assert_select "input[type=submit][name=confirmed]"
    end
    assert_not PersonMentor.exists?(timesheet_id: @tinsel.id)
  end

  test "answering the question records the pass and the grants together" do
    become_graduate
    recommended_position("Dirt - Green Dot")
    hold_mentee_position(@tinsel.person)

    answer_pass

    assert_redirected_to shift_path
    assert_equal "Recorded 1 mentee. Tinsel joined the Green Dot Cadre, with Dirt - Green Dot, and no longer holds " \
                 "Green Dot Mentee.", flash[:success]
    assert_equal PersonMentor::STATUS_PASS, PersonMentor.find_by!(timesheet_id: @tinsel.id).status
    assert PersonTeam.exists?(team_id: @training.team_id, person_id: @tinsel.person_id)
    assert_not PersonPosition.exists?(person_id: @tinsel.person_id, position_id: @mentee_position.id)
  end

  test "without the graduate role a pass is recorded at once, and grants nothing even when sent" do
    hold_mentee_position(@tinsel.person)

    answer_pass

    assert_redirected_to shift_path
    assert_equal PersonMentor::STATUS_PASS, PersonMentor.find_by!(timesheet_id: @tinsel.id).status
    assert_not PersonTeam.exists?(team_id: @training.team_id, person_id: @tinsel.person_id)
    assert PersonPosition.exists?(person_id: @tinsel.person_id, position_id: @mentee_position.id)

    get shift_path
    assert_includes response.body, "A Green Dot Training graduate can add them to the team."
  end

  test "a recorded pass a graduate has not finished offers Grant Team Positions, which asks about that mentee" do
    become_graduate
    hold_mentee_position(@tinsel.person)
    walk(@tinsel, @ferrous, status: PersonMentor::STATUS_PASS)

    get shift_path
    assert_select "button[type=submit][name=grant_for][value=?]", @tinsel.id.to_s, text: /Grant Team Positions/

    post shift_path, params: { walks: { @tinsel.id => walk_params([@ferrous.id], status: PersonMentor::STATUS_PASS) },
                               grant_for: @tinsel.id }
    assert_response :unprocessable_entity
    assert_select "dialog#pass-dialog"
    assert_equal "confirmed", css_select(%(form[action="#{shift_path}"] [type=submit])).first["name"],
                 "Record Pass is the form's default button, so Enter in the dialog presses it"
  end

  test "a general note typed before the pass question rides Record Pass" do
    become_graduate
    hold_mentee_position(@tinsel.person)

    save_walk(mentor_id: @ferrous.id, status: PersonMentor::STATUS_PASS,
              general_notes: { @tinsel.person_id => "Ready for the team." })
    assert_response :unprocessable_entity
    assert_select "dialog#pass-dialog"
    assert_select "textarea#general-note-#{@tinsel.person_id}", text: /Ready for the team\./
    assert_not PersonMentoringNote.exists?(person_id: @tinsel.person_id)

    post shift_path, params: { walks: { @tinsel.id => walk_params([@ferrous.id], status: PersonMentor::STATUS_PASS) },
                               confirmed: "Record Pass", grants: { @tinsel.id => { join: "0", revoke: "0" } },
                               general_notes: { @tinsel.person_id => "Ready for the team." } }
    assert_redirected_to shift_path
    assert_equal ["Ready for the team."], PersonMentoringNote.where(person_id: @tinsel.person_id).pluck(:notes)
  end

  test "a pass with nothing left to grant is saved without the question" do
    become_graduate
    PersonTeam.create!(team_id: @training.team_id, person_id: @tinsel.person_id)

    save_walk(mentor_id: @ferrous.id, status: PersonMentor::STATUS_PASS)

    assert_redirected_to shift_path
    assert_equal PersonMentor::STATUS_PASS, PersonMentor.find_by!(timesheet_id: @tinsel.id).status
  end
end
