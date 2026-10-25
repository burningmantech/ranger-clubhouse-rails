# frozen_string_literal: true

require "test_helper"

# Training > Online Course Progress report: the tightened Admin/Trainer gate
# (Dirt Mentors and VCs see the tree but not this page), year and position
# scoping, direct-enrollment rendering, the filter bar, and the CSV export.
class Training::OnlineCourseProgressControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include ReportCardTestHelper     # assert_report_card / card_answer
  include ActiveSupport::Testing::TimeHelpers

  YEAR = 2026

  setup do
    travel_to Time.zone.local(YEAR, 10, 1, 12, 0, 0)
    Rails.cache.clear
    Current.reset

    Position.create!(id: Position::TRAINING, title: "Training",
                     type: Position::TYPE_TRAINING, active: true)
    Position.create!(id: Position::GREEN_DOT_TRAINING, title: "Green Dot Training",
                     type: Position::TYPE_TRAINING, active: true)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::TRAINER, "Trainer")
    ensure_role(Role::MENTOR, "Mentor")
    ensure_role(Role::ART_TRAINER_BASE | Position::GREEN_DOT_TRAINING, "Green Dot Interface")

    @trainer = person(:echelon_ranger)
    @mentor = person(:ranger_with_custom_gender)
    @art_trainer = person(:retired_ranger)
    @outsider = person(:inactive_ranger)

    grant_role(@trainer, Role::TRAINER)
    grant_role(@mentor, Role::MENTOR)
    grant_role(@art_trainer, Role::ART_TRAINER_BASE | Position::GREEN_DOT_TRAINING)

    # The report reads this one table; the shared fixtures pre-enroll
    # active_ranger for 2026 and would pollute the scoping and empty-state
    # assertions, so every test starts from an empty roster.
    PersonOnlineCourse.delete_all
    @course = online_course(:training_all_2026)
  end

  teardown do
    Current.reset
    Rails.cache.clear
    travel_back
  end

  def enroll(person, enrolled_at:, completed_at: nil, year: YEAR, position_id: Position::TRAINING)
    PersonOnlineCourse.create!(person_id: person.id, online_course: @course,
                               year:, position_id:, enrolled_at:, completed_at:)
  end

  test "a trainer sees who enrolled, who finished, and who came in directly" do
    finished = person(:active_ranger)
    plodding = person(:alpha_ranger)
    direct = person(:auditor_ranger)
    enroll(finished, enrolled_at: Time.zone.local(YEAR, 1, 18, 9, 14),
                     completed_at: Time.zone.local(YEAR, 1, 19, 21, 40))
    enroll(plodding, enrolled_at: Time.zone.local(YEAR, 4, 12, 10, 31))
    enroll(direct, enrolled_at: nil, completed_at: Time.zone.local(YEAR, 4, 1, 16, 27))

    sign_in_as(@trainer)
    get training_online_course_progress_path("in-person", year: YEAR)

    assert_response :success
    assert_select "h1", text: /Online Course Progress/
    [finished, plodding, direct].each do |p|
      assert_select "td,th", text: p.callsign
    end
    # The wall-clock digits render unchanged (parse_time_in_zone stamps, never shifts).
    assert_match "Sun Jan 18 @ 09:14", response.body
    # Read off the row, not the page: the card says "direct enrollment" too.
    assert_select "td", text: /direct enrollment/, count: 1
  end

  # What the mark in the Enrolled column means is in the card under the stat
  # row, and a report with no one enrolled has neither. No one here came in
  # directly: the Direct Enrollment box is there at zero, so the card is too.
  test "the card explains direct enrollment where there is a report to read" do
    enroll(person(:auditor_ranger), enrolled_at: Time.zone.local(YEAR, 4, 12, 10, 31))

    sign_in_as(@trainer)
    get training_online_course_progress_path("in-person", year: YEAR)

    assert_report_card
    assert_match(/enrolled directly in Moodle/, card_answer("What does direct enrollment mean?"))

    get training_online_course_progress_path("in-person", year: YEAR - 1)

    assert_match(/No one has enrolled/, response.body)
    assert_report_card count: 0
  end

  test "rows are scoped to the year and the slug's position" do
    last_year = person(:active_ranger)
    other_art = person(:alpha_ranger)
    enroll(last_year, enrolled_at: Time.zone.local(YEAR - 1, 2, 1, 8, 0), year: YEAR - 1)
    enroll(other_art, enrolled_at: Time.zone.local(YEAR, 2, 1, 8, 0),
                      position_id: Position::GREEN_DOT_TRAINING)

    sign_in_as(@trainer)
    get training_online_course_progress_path("in-person", year: YEAR)

    assert_response :success
    assert_match(/No one has enrolled/, response.body)
  end

  test "the filters narrow by status, progress, and callsign" do
    active = person(:active_ranger)     # TestRanger
    retired = person(:retired_ranger)   # RetiredRanger
    enroll(active, enrolled_at: Time.zone.local(YEAR, 1, 18, 9, 14),
                   completed_at: Time.zone.local(YEAR, 1, 19, 21, 40))
    enroll(retired, enrolled_at: Time.zone.local(YEAR, 3, 2, 14, 55))

    sign_in_as(@trainer)

    get training_online_course_progress_path("in-person", year: YEAR)
    assert_select "td,th", text: active.callsign
    assert_select "td,th", text: retired.callsign

    get training_online_course_progress_path("in-person", year: YEAR, status: Person::RETIRED)
    assert_select "td,th", text: retired.callsign
    assert_select "td,th", text: active.callsign, count: 0

    get training_online_course_progress_path("in-person", year: YEAR, progress: "in-progress")
    assert_select "td,th", text: retired.callsign
    assert_select "td,th", text: active.callsign, count: 0
    assert_match "Progress: In progress", response.body

    get training_online_course_progress_path("in-person", year: YEAR, progress: "completed")
    assert_select "td,th", text: active.callsign
    assert_select "td,th", text: retired.callsign, count: 0

    get training_online_course_progress_path("in-person", year: YEAR, callsign: "testrang")
    assert_select "td,th", text: active.callsign
    assert_select "td,th", text: retired.callsign, count: 0

    # A filter that matches no one still reports the season totals.
    get training_online_course_progress_path("in-person", year: YEAR, callsign: "no one")
    assert_match(/No one matched the current filters/, response.body)
  end

  test "the CSV export carries the whole report, not the filtered view" do
    active = person(:active_ranger)
    direct = person(:auditor_ranger)
    enroll(active, enrolled_at: Time.zone.local(YEAR, 1, 18, 9, 14),
                   completed_at: Time.zone.local(YEAR, 1, 19, 21, 40))
    enroll(direct, enrolled_at: nil, completed_at: Time.zone.local(YEAR, 4, 1, 16, 27))

    sign_in_as(@trainer)
    get training_online_course_progress_path("in-person", year: YEAR, format: :csv, callsign: "no one")

    assert_response :success
    lines = response.body.split("\n")
    assert_equal "Callsign,Status,Moodle Username,Enrolled At (Pacific),Completed At (Pacific)", lines.first
    assert_equal 3, lines.size
    assert_match(/#{active.callsign},active,.*,#{YEAR}-01-18 09:14,#{YEAR}-01-19 21:40/, response.body)
    # A direct enrollment exports an empty Enrolled cell.
    assert_match(/#{direct.callsign},auditor,.*,,#{YEAR}-04-01 16:27/, response.body)
  end

  test "the gate is tighter than the tree: mentors are turned away, admins pass" do
    sign_in_as(@mentor)
    get training_online_course_progress_path("in-person", year: YEAR)
    assert_redirected_to me_root_path
    assert_match(/not authorized/, flash[:error])

    admin = person(:active_ranger)
    grant_role(admin, Role::ADMIN)
    sign_in_as(admin)
    get training_online_course_progress_path("in-person", year: YEAR)
    assert_response :success
  end

  test "an ART tree shows its own empty report, never In-Person's data" do
    enroll(person(:active_ranger), enrolled_at: Time.zone.local(YEAR, 1, 18, 9, 14))
    grant_role(@art_trainer, Role::TRAINER)

    sign_in_as(@art_trainer)
    get training_online_course_progress_path("green-dot", year: YEAR)

    assert_response :success
    assert_select "h1", text: /Green Dot Training/
    assert_match(/No one has enrolled/, response.body)
  end

  test "an unauthorized person is turned away by the tree gate" do
    sign_in_as(@outsider)

    get training_online_course_progress_path("in-person", year: YEAR)
    assert_redirected_to me_root_path
    assert_match(/not authorized/, flash[:error])
  end
end
