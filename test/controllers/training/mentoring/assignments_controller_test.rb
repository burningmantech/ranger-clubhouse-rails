# frozen_string_literal: true

require "test_helper"

# Training › Mentoring › Mentor Assignment: the picker, one shift's roster and
# its save, a shift still to come, and a past year's roster, recorded like the current one.
class Training::Mentoring::AssignmentsControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include ArtMentoringTestHelper
  include PersonTestFactory
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

  def save_walk(mentor_id:, status: PersonMentor::STATUS_PENDING, notes: "", entry: @tinsel, path: shift_path)
    post path, params: { walks: { entry.id => { mentor_ids: [mentor_id, ""], status:, notes: } } }
  end

  test "the picker shows each mentoring shift as a card that opens its roster" do
    get training_mentoring_assignment_path(SLUG)

    assert_response :success
    assert_select "a[href=?]", shift_path, text: /Manage/
    assert_includes response.body, "1 need a mentor", "the shift has ended, and no one was paired with Tinsel"
    assert_not_includes response.body, "awaiting a verdict", "a verdict waits on a mentor"
  end

  test "a shift's roster offers the mentors on shift before everyone else holding the position" do
    get shift_path

    assert_response :success
    select = "select#walk-#{@tinsel.id}-mentor-1"
    assert_select "#{select} optgroup[label=?] option", "On shift", text: /\AFerrous · signed in/
    assert_select "#{select} optgroup[label=?] option", "Other mentors", text: "Cinder"
    assert_select "select[name=?]", "walks[#{@tinsel.id}][mentor_ids][]", count: ArtMentoring::Assignment::MENTOR_SLOTS
    assert_select "form[action=?]", shift_path
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

  test "two mentors are recorded, and the roster selects both" do
    post shift_path, params: { walks: { @tinsel.id => { mentor_ids: [@ferrous.id, @cinder.id, ""],
                                                        status: PersonMentor::STATUS_PENDING, notes: "" } } }

    assert_redirected_to shift_path
    assert_equal [@cinder.id, @ferrous.id].sort, PersonMentor.where(timesheet_id: @tinsel.id).pluck(:mentor_id).sort

    get shift_path
    assert_select "select#walk-#{@tinsel.id}-mentor-1 option[selected][value=?]", @ferrous.id.to_s
    assert_select "select#walk-#{@tinsel.id}-mentor-2 option[selected][value=?]", @cinder.id.to_s
    assert_select "select#walk-#{@tinsel.id}-mentor-3 option[selected]:not([value=''])", count: 0
  end

  test "a refused row comes back at 422 with its reason and what was typed" do
    save_walk(mentor_id: "", status: PersonMentor::STATUS_BONK)

    assert_response :unprocessable_entity
    assert_includes response.body, "Pick a mentor before recording a result."
    assert_select "select#walk-#{@tinsel.id}-status option[selected][value=?]", PersonMentor::STATUS_BONK
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
    post shift_path, params: { walks: { @tinsel.id => { mentor_ids: [@ferrous.id], status: PersonMentor::STATUS_PASS, notes: "" } },
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

    post shift_path, params: { walks: { @tinsel.id => { mentor_ids: [@ferrous.id], status: PersonMentor::STATUS_PASS, notes: "" } },
                               grant_for: @tinsel.id }
    assert_response :unprocessable_entity
    assert_select "dialog#pass-dialog"
    assert_equal "confirmed", css_select(%(form[action="#{shift_path}"] [type=submit])).first["name"],
                 "Record Pass is the form's default button, so Enter in the dialog presses it"
  end

  test "a pass with nothing left to grant is saved without the question" do
    become_graduate
    PersonTeam.create!(team_id: @training.team_id, person_id: @tinsel.person_id)

    save_walk(mentor_id: @ferrous.id, status: PersonMentor::STATUS_PASS)

    assert_redirected_to shift_path
    assert_equal PersonMentor::STATUS_PASS, PersonMentor.find_by!(timesheet_id: @tinsel.id).status
  end
end
