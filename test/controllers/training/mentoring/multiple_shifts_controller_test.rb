# frozen_string_literal: true

require "test_helper"

# Training › Mentoring › Multiple Shifts: the mentees with more than one
# mentee shift, their shift chips, the filters and CSV, and the gate.
class Training::Mentoring::MultipleShiftsControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include ArtMentoringTestHelper
  include PersonTestFactory
  include ReportCardTestHelper
  include ActiveSupport::Testing::TimeHelpers

  YEAR = 2026
  SLUG = "green-dot"

  setup do
    travel_to Time.zone.local(YEAR, 9, 2, 19, 0, 0)
    Rails.cache.clear
    Current.reset
    setup_art_mentoring

    ensure_role(Role::ART_TRAINER_BASE | Position::GREEN_DOT_TRAINING, "Green Dot Interface")
    grant_role(person(:retired_ranger), Role::ART_TRAINER_BASE | Position::GREEN_DOT_TRAINING)

    last_night = mentee_shift(Time.zone.local(YEAR, 9, 1, 17, 45, 0))
    tonight = mentee_shift(Time.zone.local(YEAR, 9, 2, 17, 45, 0))
    tomorrow = mentee_shift(Time.zone.local(YEAR, 9, 3, 5, 45, 0))
    @tinsel = create_person("Tinsel")
    first = mentee_entry(@tinsel, last_night.begins, off_duty: last_night.ends, slot: last_night)
    walk(first, create_person("Ferrous"), status: PersonMentor::STATUS_PASS)
    mentee_entry(@tinsel, tonight.begins, slot: tonight)
    @moonrake = create_person("Moonrake")
    mentee_entry(@moonrake, last_night.begins, off_duty: last_night.ends, slot: last_night)
    sign_up(@moonrake, tomorrow)

    sign_in_as(person(:retired_ranger))
  end

  teardown do
    Current.reset
    Rails.cache.clear
    travel_back
  end

  def multiple_shifts_path(year: YEAR, **) = training_mentoring_multiple_shifts_path(SLUG, year:, **)

  test "each mentee with more than one shift is a row of shift chips" do
    get multiple_shifts_path

    assert_response :success
    assert_select "h1", text: /Green Dot Training Multiple Mentee Shifts/
    assert_report_card
    assert_select "tr#multiple-shifts-#{@tinsel.id}", text: /Tue 9\/1 17:45.*Wed 9\/2 17:45 · on shift.*Passed.*Ferrous/m
    assert_select "tr#multiple-shifts-#{@moonrake.id}", text: /Thu 9\/3 05:45 · signed up/
  end

  test "the filters narrow the rows, and the CSV follows them" do
    get multiple_shifts_path(kind: ArtMentoring::MultipleShiftsReport::SIGNED_UP)

    assert_select "tr#multiple-shifts-#{@moonrake.id}"
    assert_select "tr#multiple-shifts-#{@tinsel.id}", count: 0
    assert_includes response.body, "Kind: Signed up again"

    get multiple_shifts_path(callsign: "tins", format: :csv)

    assert_response :success
    assert_equal ["Mentee,Rangered,Signed Up,Shifts,Latest Verdict,Mentors",
                  "Tinsel,2,0,2026-09-01 17:45; 2026-09-02 17:45 (on shift),Passed,Ferrous"],
                 response.body.lines(chomp: true)
  end

  test "a year without repeat mentees says so" do
    get multiple_shifts_path(year: YEAR - 1)

    assert_response :success
    assert_includes response.body, "No mentee has more than one mentee shift in #{YEAR - 1}."
  end

  test "an In-Person trainer cannot open an ART's multiple shifts" do
    ensure_role(Role::TRAINER, "Trainer")
    grant_role(person(:echelon_ranger), Role::TRAINER)
    sign_in_as(person(:echelon_ranger))

    get multiple_shifts_path

    assert_redirected_to me_root_path
  end
end
