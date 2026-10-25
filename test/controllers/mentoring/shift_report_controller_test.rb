# frozen_string_literal: true

require "test_helper"

class Mentoring::ShiftReportControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include TrainingSlotTestHelper
  include PersonTestFactory
  include ActiveSupport::Testing::TimeHelpers

  YEAR = 2026
  DENY_MESSAGE = "Admin or Mentor role required to view the shift report."

  setup do
    # Event week, so on-duty entries opened this morning read as current-year.
    travel_to Time.zone.local(YEAR, 8, 25, 12, 0, 0)
    Rails.cache.clear
    Current.reset

    @alpha_position = Position.create!(id: Position::ALPHA, title: "Alpha",
                                       type: Position::TYPE_FRONTLINE, active: true)
    @mentor_position = Position.create!(id: Position::MENTOR, title: "Mentor",
                                        type: Position::TYPE_MENTORING, active: true)
    Position.create!(id: Position::MENTOR_MITTEN, title: "Mentor Mitten",
                     type: Position::TYPE_MENTORING, active: true)
    @khaki_position = Position.create!(id: Position::MENTOR_KHAKI, title: "Mentor Khaki",
                                       type: Position::TYPE_MENTORING, active: true)

    # The chosen shift begins 07:00, so the window is exactly 06:00..10:00.
    # Two mentor shifts sit ON the endpoints (both included), one begins 30
    # minutes past the +3h edge (excluded), and the Khaki shift has no
    # sign-ups.
    @alpha_slot = create_slot(@alpha_position, begins: Time.zone.local(YEAR, 8, 26, 7, 0, 0),
                              ends: Time.zone.local(YEAR, 8, 26, 13, 0, 0), description: "Alpha shift one")
    @mentor_slot = create_slot(@mentor_position, begins: Time.zone.local(YEAR, 8, 26, 7, 0, 0),
                               ends: Time.zone.local(YEAR, 8, 26, 13, 0, 0), description: "Mentor shift")
    @early_edge_slot = create_slot(@mentor_position, begins: Time.zone.local(YEAR, 8, 26, 6, 0, 0),
                                   ends: Time.zone.local(YEAR, 8, 26, 12, 0, 0), description: "Early edge shift")
    @late_edge_slot = create_slot(@mentor_position, begins: Time.zone.local(YEAR, 8, 26, 10, 0, 0),
                                  ends: Time.zone.local(YEAR, 8, 26, 16, 0, 0), description: "Late edge shift")
    create_slot(@khaki_position, begins: Time.zone.local(YEAR, 8, 26, 6, 30, 0),
                ends: Time.zone.local(YEAR, 8, 26, 12, 30, 0), description: "Khaki shift")
    @late_mentor_slot = create_slot(@mentor_position, begins: Time.zone.local(YEAR, 8, 26, 10, 30, 0),
                                    ends: Time.zone.local(YEAR, 8, 26, 16, 30, 0), description: "Late mentor shift")

    # Fresh people rather than fixture ones: person_mentor.yml pre-seeds bonk
    # history for several fixture people, which would bleed into the badges.
    @bonked_alpha = create_person("ShiftAlphaOne")
    @clean_alpha = create_person("ShiftAlphaTwo")
    @seasoned_mentor = create_person("ShiftMentor", years: [2012, 2013, 2014, 2016])
    @early_edge_mentor = create_person("ShiftEdgeEarly", years: [2024])
    @late_edge_mentor = create_person("ShiftEdgeLate", years: [2024])
    @late_mentor = create_person("ShiftLateMentor", years: [2020])

    PersonSlot.create!(person_id: @bonked_alpha.id, slot_id: @alpha_slot.id)
    PersonSlot.create!(person_id: @clean_alpha.id, slot_id: @alpha_slot.id)
    PersonSlot.create!(person_id: @seasoned_mentor.id, slot_id: @mentor_slot.id)
    PersonSlot.create!(person_id: @early_edge_mentor.id, slot_id: @early_edge_slot.id)
    PersonSlot.create!(person_id: @late_edge_mentor.id, slot_id: @late_edge_slot.id)
    PersonSlot.create!(person_id: @late_mentor.id, slot_id: @late_mentor_slot.id)

    mentor_of_record = person(:active_ranger)
    PersonMentor.create!(person: @bonked_alpha, mentor: mentor_of_record,
                         mentor_year: 2019, status: PersonMentor::STATUS_SELF_BONK)
    PersonMentor.create!(person: @bonked_alpha, mentor: mentor_of_record,
                         mentor_year: 2023, status: PersonMentor::STATUS_BONK)

    @admin = person(:auditor_ranger)
    @mentor = person(:echelon_ranger)
    @outsider = person(:inactive_ranger)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::MENTOR, "Mentor")
    ensure_role(Role::VC, "Volunteer Coordinator")
    grant_role(@admin, Role::ADMIN)
    grant_role(@mentor, Role::MENTOR)
    grant_role(@outsider, Role::VC)

    Current.person = @admin
  end

  teardown do
    Current.reset
    Rails.cache.clear
    travel_back
  end

  # --- authorization ---

  test "an admin can view the page" do
    sign_in_as(@admin)
    get mentoring_shift_report_path
    assert_response :success
  end

  test "a mentor can view the page" do
    sign_in_as(@mentor)
    get mentoring_shift_report_path
    assert_response :success
  end

  test "a role outside the gate is turned away" do
    sign_in_as(@outsider)
    get mentoring_shift_report_path
    assert_redirected_to me_root_path
    assert_equal DENY_MESSAGE, flash[:error]
  end

  # --- the picker ---

  test "the shift cards stand in for the report until a shift is chosen" do
    sign_in_as(@mentor)

    get mentoring_shift_report_path

    assert_response :success
    assert_match "View Shift Report", response.body
    assert_no_match(/Scheduled for the Alpha shift/, response.body)
  end

  test "choosing a shift replaces the cards with the report" do
    sign_in_as(@mentor)

    get mentoring_shift_report_path(slot_id: @alpha_slot.id)

    assert_response :success
    assert_match(/Scheduled for the Alpha shift/, response.body)
    assert_no_match(/View Shift Report/, response.body)
    assert_match "Choose another shift", response.body
  end

  test "the picker offers only the year's active Alpha shifts" do
    create_slot(@alpha_position, begins: Time.zone.local(YEAR, 8, 27, 7, 0, 0),
                ends: Time.zone.local(YEAR, 8, 27, 13, 0, 0),
                description: "Inactive alpha shift", active: false)
    create_slot(@alpha_position, begins: Time.zone.local(2025, 8, 26, 7, 0, 0),
                ends: Time.zone.local(2025, 8, 26, 13, 0, 0), description: "Prior year alpha")
    sign_in_as(@mentor)

    get mentoring_shift_report_path

    assert_response :success
    assert_match "Alpha shift one", response.body
    assert_no_match(/Inactive alpha shift/, response.body)
    assert_no_match(/Prior year alpha/, response.body)
    # Only Alpha slots are offered, not the window's other positions.
    assert_no_match(/Mentor shift/, response.body)
  end

  test "the year selector switches the picker" do
    create_slot(@alpha_position, begins: Time.zone.local(2025, 8, 26, 7, 0, 0),
                ends: Time.zone.local(2025, 8, 26, 13, 0, 0), description: "Prior year alpha")
    sign_in_as(@mentor)

    get mentoring_shift_report_path(year: 2025)

    assert_response :success
    assert_match "Prior year alpha", response.body
    assert_no_match(/Alpha shift one/, response.body)
  end

  test "a malformed or out-of-range year falls back to the current year" do
    sign_in_as(@mentor)

    get mentoring_shift_report_path(year: "abc")
    assert_response :success
    assert_match "Alpha shift one", response.body

    get mentoring_shift_report_path(year: 1999)
    assert_response :success
    assert_match "Alpha shift one", response.body
  end

  # --- scheduled mode ---

  test "the scheduled report shows the window's sign-ups in their groups" do
    sign_in_as(@mentor)

    get mentoring_shift_report_path(slot_id: @alpha_slot.id)

    assert_response :success
    assert_match "Scheduled for the Alpha shift", response.body
    assert_select "#shift-report-alphas"
    assert_select "#shift-report-mentors"
    assert_select "#shift-report-cheetahs"
    assert_select "#shift-report-operations"
    assert_match @bonked_alpha.callsign, response.body
    assert_match @clean_alpha.callsign, response.body
    assert_match @seasoned_mentor.callsign, response.body
    # The window is inclusive of both endpoints...
    assert_match @early_edge_mentor.callsign, response.body
    assert_match @late_edge_mentor.callsign, response.body
    # ...and this shift begins 30 minutes past the +3h edge.
    assert_no_match(/#{@late_mentor.callsign}/, response.body)
  end

  test "alphas carry prior bonks and everyone else their rangering history" do
    sign_in_as(@mentor)

    get mentoring_shift_report_path(slot_id: @alpha_slot.id)

    assert_response :success
    assert_match "Bonked 2019", response.body
    assert_match "Bonked 2023", response.body
    assert_match "4 events", response.body
    assert_match "2012 - 2014, 2016", response.body
  end

  test "an empty shift is called out and counted as unfilled" do
    sign_in_as(@mentor)

    get mentoring_shift_report_path(slot_id: @alpha_slot.id)

    assert_response :success
    assert_match "No sign-ups yet for this shift", response.body
    # Only the Khaki shift is empty; the slotless Mitten position renders its
    # placeholder line but is not an unfilled shift.
    assert_select "div", text: "Unfilled Shifts" do |labels|
      assert_equal "1Unfilled Shifts", labels.first.parent.text.strip
    end
    assert_match "No Mentor Mitten shifts are scheduled around this Alpha shift", response.body
  end

  test "an inactive shift inside the window is left out" do
    create_slot(@mentor_position, begins: Time.zone.local(YEAR, 8, 26, 8, 0, 0),
                ends: Time.zone.local(YEAR, 8, 26, 14, 0, 0),
                description: "Inactive mentor shift", active: false)
    sign_in_as(@mentor)

    get mentoring_shift_report_path(slot_id: @alpha_slot.id)

    assert_response :success
    assert_no_match(/Inactive mentor shift/, response.body)
  end

  test "a non-Alpha slot id is rejected with the picker still on screen" do
    sign_in_as(@mentor)

    get mentoring_shift_report_path(slot_id: @mentor_slot.id)

    assert_response :success
    assert_match "not an Alpha shift", flash[:error]
    assert_no_match(/Scheduled for the Alpha shift/, response.body)
  end

  test "an unknown slot id is rejected the same way" do
    sign_in_as(@mentor)

    get mentoring_shift_report_path(slot_id: 999_999)

    assert_response :success
    assert_match "not an Alpha shift", flash[:error]
    assert_no_match(/Scheduled for the Alpha shift/, response.body)
  end

  # --- on-duty mode ---

  test "the on-duty report lists open shifts for the current year only" do
    on_now = create_person("ShiftOnDuty", years: [2021, 2022])
    off_already = create_person("ShiftWentHome", years: [2018])
    last_year = create_person("ShiftLastYear")
    Timesheet.create!(person: on_now, position_id: Position::MENTOR,
                      on_duty: Time.zone.local(YEAR, 8, 25, 8, 0, 0), additional_notes: "test shift")
    Timesheet.create!(person: off_already, position_id: Position::MENTOR,
                      on_duty: Time.zone.local(YEAR, 8, 25, 2, 0, 0),
                      off_duty: Time.zone.local(YEAR, 8, 25, 8, 0, 0), additional_notes: "test shift")
    Timesheet.create!(person: last_year, position_id: Position::MENTOR,
                      on_duty: Time.zone.local(2025, 8, 25, 8, 0, 0), additional_notes: "test shift")
    Timesheet.create!(person: @bonked_alpha, position_id: Position::ALPHA,
                      on_duty: Time.zone.local(YEAR, 8, 25, 9, 0, 0), additional_notes: "test shift")
    sign_in_as(@mentor)

    get mentoring_shift_report_path(on_duty: 1)

    assert_response :success
    assert_match "On duty now", response.body
    assert_match on_now.callsign, response.body
    assert_no_match(/#{off_already.callsign}/, response.body)
    assert_no_match(/#{last_year.callsign}/, response.body)
    # Elapsed durations, measured to the travelled-to noon.
    assert_match "4:00", response.body
    assert_match "3:00", response.body
    # The Alpha on duty still carries their bonk history.
    assert_match @bonked_alpha.callsign, response.body
    assert_match "Bonked 2023", response.body
  end

  test "the on-duty report ignores the year param" do
    last_year = create_person("ShiftLastYear")
    Timesheet.create!(person: last_year, position_id: Position::MENTOR,
                      on_duty: Time.zone.local(2025, 8, 25, 8, 0, 0), additional_notes: "test shift")
    on_now = create_person("ShiftOnDuty")
    Timesheet.create!(person: on_now, position_id: Position::MENTOR,
                      on_duty: Time.zone.local(YEAR, 8, 25, 8, 0, 0), additional_notes: "test shift")
    sign_in_as(@mentor)

    get mentoring_shift_report_path(on_duty: 1, year: 2025)

    assert_response :success
    assert_match on_now.callsign, response.body
    assert_no_match(/#{last_year.callsign}/, response.body)
    assert_match "current year", response.body
  end

  test "an empty on-duty report collapses to a single message" do
    sign_in_as(@mentor)

    get mentoring_shift_report_path(on_duty: 1)

    assert_response :success
    assert_match "No one is currently on duty", response.body
    assert_no_match(/No one is on duty in these positions/, response.body)
    assert_no_match(/Unfilled Shifts/, response.body)
  end
end
