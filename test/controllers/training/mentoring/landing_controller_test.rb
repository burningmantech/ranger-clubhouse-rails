# frozen_string_literal: true

require "test_helper"

# Training › Mentoring: only an ART mentoring training has the page, only its
# trainers (and admins) see it, and the "right now" parts are this year's alone.
class Training::Mentoring::LandingControllerTest < ActionDispatch::IntegrationTest
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
  end

  teardown do
    Current.reset
    Rails.cache.clear
    travel_back
  end

  test "a trainer sees who is on a mentee shift now, and who has no mentor yet" do
    slot = mentee_shift(Time.zone.local(YEAR, 9, 2, 17, 45, 0))
    mentee_entry(create_person("Lodestar"), slot.begins, slot:)

    sign_in_as(@art_trainer)
    get training_mentoring_path(SLUG)

    assert_response :success
    assert_select "h1", text: /Green Dot Training Mentoring/
    assert_select "a[href=?]", training_mentoring_assignment_shift_path(SLUG, slot.id, year: YEAR)
    assert_includes response.body, "Lodestar"
    assert_includes response.body, "No mentor yet"
    assert_select "a[href=?]", training_mentoring_assignment_path(SLUG, year: YEAR), text: /Mentor Assignment/
  end

  test "the landing opens Verdicts and Multiple Shifts with their counts" do
    slot = mentee_shift(Time.zone.local(YEAR, 9, 1, 17, 45, 0))
    entry = mentee_entry(create_person("Lodestar"), slot.begins, off_duty: slot.ends, slot:)
    walk(entry, create_person("Ferrous"), status: PersonMentor::STATUS_PASS)

    sign_in_as(@art_trainer)
    get training_mentoring_path(SLUG)

    assert_select "a[href=?]", training_mentoring_verdicts_path(SLUG, year: YEAR), text: /Verdicts.*1 verdict recorded/m
    assert_select "a[href=?]", training_mentoring_multiple_shifts_path(SLUG, year: YEAR), text: /Multiple Shifts.*0 mentees/m
  end

  # Reported 2026-10-22: after the event the tile read 0 while no mentee had a
  # mentor. Each mentee is counted once: no mentor, or a mentor and Pending.
  test "a mentee no one was paired with needs a mentor after their shift, and a paired one awaits a verdict" do
    slot = mentee_shift(Time.zone.local(YEAR, 9, 1, 17, 45, 0))
    mentee_entry(create_person("Lodestar"), slot.begins, off_duty: slot.ends, slot:)
    mentee_entry(create_person("Moonrake"), slot.begins, off_duty: slot.ends, slot:)
    walk(mentee_entry(create_person("Tinsel"), slot.begins, off_duty: slot.ends, slot:), create_person("Ferrous"))

    sign_in_as(@art_trainer)
    get training_mentoring_path(SLUG)

    assert_select "div", text: /\A\s*0\s*Mentees on Shift Now\s*\z/
    assert_select "div", text: /\A\s*2\s*Need a Mentor\s*\z/
    assert_select "div", text: /\A\s*1\s*Awaiting a Verdict\s*\z/
  end

  test "a past year shows its numbers, not who is on shift now" do
    sign_in_as(@art_trainer)
    get training_mentoring_path(SLUG, year: YEAR - 1)

    assert_response :success
    assert_includes response.body, "Awaiting a Verdict"
    assert_not_includes response.body, "On Shift Now"
    assert_not_includes response.body, "Next Mentee Shifts"
  end

  test "a team with no mentee position flagged is told so" do
    @mentee_position.update!(is_art_mentee: false)

    sign_in_as(@art_trainer)
    get training_mentoring_path(SLUG)

    assert_response :success
    assert_includes response.body, "No Mentee Position"
  end

  test "a training without ART mentoring sends the reader to its sessions" do
    @training.update!(has_art_mentoring: false)

    sign_in_as(@art_trainer)
    get training_mentoring_path(SLUG)

    assert_redirected_to training_path(SLUG)
  end

  test "an In-Person trainer cannot open an ART's mentoring pages" do
    sign_in_as(@dirt_trainer)
    get training_mentoring_path(SLUG)

    assert_redirected_to me_root_path
  end
end
