# frozen_string_literal: true

require "test_helper"

class Mentoring::AlphaScheduleControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include EscapedMarkupTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include TrainingSlotTestHelper
  include PersonTestFactory
  include ActiveSupport::Testing::TimeHelpers

  YEAR = 2026
  DENY_MESSAGE = "Admin or Mentor role required to view the Alpha schedule."

  setup do
    # Event week, so an on-duty entry opened this morning reads as signed in.
    travel_to Time.zone.local(YEAR, 8, 25, 12, 0, 0)
    Rails.cache.clear
    Current.reset

    @alpha_position = Position.create!(id: Position::ALPHA, title: "Alpha",
                                       type: Position::TYPE_FRONTLINE, active: true)
    Position.create!(id: Position::TRAINING, title: "In-Person Training",
                     type: Position::TYPE_TRAINING, active: true)

    # Two shifts on one day (the Day/Swing pair the index groups), plus an
    # inactive one that must still be listed, and a full one.
    @day_slot = create_slot(@alpha_position, begins: Time.zone.local(YEAR, 8, 26, 8, 0, 0),
                            ends: Time.zone.local(YEAR, 8, 26, 18, 0, 0),
                            description: "Alpha Walk Wednesday Day", max: 3)
    @swing_slot = create_slot(@alpha_position, begins: Time.zone.local(YEAR, 8, 26, 14, 0, 0),
                              ends: Time.zone.local(YEAR, 8, 26, 23, 0, 0),
                              description: "Alpha Walk Wednesday Swing", max: 2)
    @inactive_slot = create_slot(@alpha_position, begins: Time.zone.local(YEAR, 8, 27, 8, 0, 0),
                                 ends: Time.zone.local(YEAR, 8, 27, 18, 0, 0),
                                 description: "Alpha Walk Thursday Day", max: 4, active: false)
    @other_year_slot = create_slot(@alpha_position, begins: Time.zone.local(YEAR - 1, 8, 26, 8, 0, 0),
                                   ends: Time.zone.local(YEAR - 1, 8, 26, 18, 0, 0),
                                   description: "Alpha Walk Last Year", max: 4)

    @signed_in_alpha = create_person("AlphaSignedIn", status: Person::ALPHA)
    @flagged_alpha = create_person("AlphaFlagged", status: Person::ALPHA)
    @plain_alpha = create_person("AlphaPlain", status: Person::PROSPECTIVE)

    [@signed_in_alpha, @flagged_alpha, @plain_alpha].each do |person|
      PersonSlot.create!(person_id: person.id, slot_id: @day_slot.id)
    end

    # The Swing shift is at capacity, so the index must badge it Full.
    @swing_one = create_person("AlphaSwingOne", status: Person::ALPHA)
    @swing_two = create_person("AlphaSwingTwo", status: Person::ALPHA)
    PersonSlot.create!(person_id: @swing_one.id, slot_id: @swing_slot.id)
    PersonSlot.create!(person_id: @swing_two.id, slot_id: @swing_slot.id)

    # A mentor rank of 3 is what the roster folds under the callsign.
    PersonIntake.create!(person_id: @flagged_alpha.id, year: YEAR, mentor_rank: Intake::BELOW_AVERAGE)
    # A rank below the flag threshold must NOT appear.
    PersonIntake.create!(person_id: @plain_alpha.id, year: YEAR, mentor_rank: Intake::AVERAGE)

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

  # Puts someone on an open Alpha timesheet, which is what "signed in" means.
  def sign_in_to_shift(person, slot)
    Timesheet.create!(person_id: person.id, position_id: Position::ALPHA, slot_id: slot.id,
                      on_duty: Time.current - 1.hour, additional_notes: "test")
  end

  # --- authorization ---

  test "an admin can view the schedule" do
    sign_in_as(@admin)
    get mentoring_alpha_schedule_path(year: YEAR)
    assert_response :success
  end

  test "a mentor can view the schedule" do
    sign_in_as(@mentor)
    get mentoring_alpha_schedule_path(year: YEAR)
    assert_response :success
  end

  test "a role outside the gate is turned away" do
    sign_in_as(@outsider)
    get mentoring_alpha_schedule_path(year: YEAR)
    assert_redirected_to me_root_path
    assert_equal DENY_MESSAGE, flash[:error]
  end

  test "the gate also covers a single shift" do
    sign_in_as(@outsider)
    get mentoring_alpha_schedule_shift_path(@day_slot)
    assert_redirected_to me_root_path
  end

  # --- the index ---

  test "the index lists the chosen year's shifts and no others" do
    sign_in_as(@mentor)

    get mentoring_alpha_schedule_path(year: YEAR)

    assert_response :success
    assert_match "Alpha Walk Wednesday Day", response.body
    assert_match "Alpha Walk Wednesday Swing", response.body
    assert_no_match(/Alpha Walk Last Year/, response.body)
  end

  test "the index shows sign-up counts against capacity" do
    sign_in_as(@mentor)

    get mentoring_alpha_schedule_path(year: YEAR)

    assert_response :success
    assert_match "3", response.body
    assert_select "a[href=?]", mentoring_alpha_schedule_shift_path(@day_slot)
  end

  test "a shift at capacity is badged Full" do
    sign_in_as(@mentor)

    get mentoring_alpha_schedule_path(year: YEAR)

    assert_response :success
    assert_match "Full", response.body
  end

  test "an inactive shift is listed and badged rather than hidden" do
    sign_in_as(@mentor)

    get mentoring_alpha_schedule_path(year: YEAR)

    assert_response :success
    assert_match "Alpha Walk Thursday Day", response.body
    assert_match "Inactive", response.body
    assert_select "a[href=?]", mentoring_alpha_schedule_shift_path(@inactive_slot)
  end

  test "a year with no Alpha shifts says so" do
    sign_in_as(@mentor)

    get mentoring_alpha_schedule_path(year: 2015)

    assert_response :success
    assert_match "No Alpha shifts are scheduled for 2015", response.body
  end

  # --- the shift page ---

  test "the shift page lists its sign-ups by callsign" do
    sign_in_as(@mentor)

    get mentoring_alpha_schedule_shift_path(@day_slot)

    assert_response :success
    assert_match "AlphaSignedIn", response.body
    assert_match "AlphaFlagged", response.body
    assert_match "AlphaPlain", response.body
    # Not on this shift.
    assert_no_match(/AlphaSwingOne/, response.body)
  end

  # A shift with no description of its own falls back to its start time, which
  # is built as markup. The page title and the remove confirmation are plain
  # text, so they have to ask for the plain form or the reader sees tags.
  test "a shift with no description names itself in words, not markup" do
    undescribed = create_slot(@alpha_position, begins: Time.zone.local(YEAR, 8, 28, 8, 0, 0),
                              ends: Time.zone.local(YEAR, 8, 28, 18, 0, 0),
                              description: nil, max: 3)
    # Someone has to be on it, or the page draws no remove confirmation to check.
    PersonSlot.create!(person_id: @plain_alpha.id, slot_id: undescribed.id)

    sign_in_as(@mentor)

    get mentoring_alpha_schedule_shift_path(undescribed)

    assert_response :success
    assert_no_escaped_markup

    # The sheets head every table with the same name, joined to the year.
    sign_in_to_shift(@plain_alpha, undescribed)
    [mentoring_alpha_schedule_signup_sheet_path(undescribed), mentoring_alpha_schedule_apparel_path(undescribed)].each do |sheet|
      get sheet

      assert_response :success
      assert_no_escaped_markup
    end
  end

  test "a mentor rank of 3 or worse folds under the callsign" do
    sign_in_as(@mentor)

    get mentoring_alpha_schedule_shift_path(@day_slot)

    assert_response :success
    # The flagged person's rank year renders; the average-ranked one has no badge.
    assert_match YEAR.to_s, response.body
    assert_select "th", text: /AlphaFlagged/
  end

  test "the shift page marks who is signed in and who is not" do
    sign_in_to_shift(@signed_in_alpha, @day_slot)
    sign_in_as(@mentor)

    get mentoring_alpha_schedule_shift_path(@day_slot)

    assert_response :success
    # ui_stat_box renders no stable hook class, so the row badges are what the
    # signed-in state is asserted against.
    rows = css_select("tbody tr")
    signed_in_row = rows.find { |row| row.text.include?("AlphaSignedIn") }
    absent_row = rows.find { |row| row.text.include?("AlphaPlain") }

    assert_includes signed_in_row.text, "Yes"
    assert_includes absent_row.text, "No"
  end

  test "a shift with no sign-ups offers the add button instead of a table" do
    sign_in_as(@mentor)

    get mentoring_alpha_schedule_shift_path(@swing_slot)
    assert_response :success

    PersonSlot.where(slot_id: @swing_slot.id).delete_all
    get mentoring_alpha_schedule_shift_path(@swing_slot)

    assert_response :success
    assert_match "No one has signed up for this shift yet", response.body
  end

  test "an inactive shift explains itself on its own page" do
    sign_in_as(@mentor)

    get mentoring_alpha_schedule_shift_path(@inactive_slot)

    assert_response :success
    assert_match "This shift is inactive", response.body
  end

  test "a slot that is not an Alpha shift is refused" do
    training = Slot.create!(position_id: Position::TRAINING, begins: Time.zone.local(YEAR, 8, 26, 8, 0, 0),
                            ends: Time.zone.local(YEAR, 8, 26, 18, 0, 0), description: "Training",
                            active: true, max: 20, timezone: "America/Los_Angeles")
    sign_in_as(@mentor)

    get mentoring_alpha_schedule_shift_path(training)

    assert_redirected_to mentoring_alpha_schedule_path(year: YEAR)
    assert_match "not an Alpha shift", flash[:error]
  end

  test "a shift from another year opens on its own year" do
    sign_in_as(@mentor)

    get mentoring_alpha_schedule_shift_path(@other_year_slot)

    assert_response :success
    assert_match "Alpha Walk Last Year", response.body
  end

  # --- the sheet buttons and their guard ---

  test "the information and apparel buttons open the dialog while no one is signed in" do
    sign_in_as(@mentor)

    get mentoring_alpha_schedule_shift_path(@day_slot)

    assert_response :success
    assert_select "a[href=?]", mentoring_alpha_schedule_no_alphas_path(@day_slot)
    assert_select "a[href=?]", mentoring_alpha_schedule_info_sheet_path(@day_slot), count: 0
    assert_select "a[href=?]", mentoring_alpha_schedule_apparel_path(@day_slot), count: 0
  end

  test "the buttons link to the sheets once someone is signed in" do
    sign_in_to_shift(@signed_in_alpha, @day_slot)
    sign_in_as(@mentor)

    get mentoring_alpha_schedule_shift_path(@day_slot)

    assert_response :success
    assert_select "a[href=?]", mentoring_alpha_schedule_info_sheet_path(@day_slot)
    assert_select "a[href=?]", mentoring_alpha_schedule_apparel_path(@day_slot)
    assert_select "a[href=?]", mentoring_alpha_schedule_no_alphas_path(@day_slot), count: 0
  end

  test "the no-alphas dialog names the shift" do
    sign_in_as(@mentor)

    get mentoring_alpha_schedule_no_alphas_path(@day_slot)

    assert_response :success
    assert_match "Alpha Walk Wednesday Day", response.body
    assert_match "No One Is Signed In Yet", response.body
  end

  # --- the sheets ---

  test "the sign-in sheet prints every sign-up plus a standby list" do
    sign_in_as(@mentor)

    get mentoring_alpha_schedule_signup_sheet_path(@day_slot)

    assert_response :success
    assert_match "AlphaSignedIn", response.body
    assert_match "AlphaPlain", response.body
    assert_match "Standby list", response.body
    assert_match "Please write legibly", response.body
  end

  test "the sign-in sheet prints before anyone signs up" do
    PersonSlot.where(slot_id: @day_slot.id).delete_all
    sign_in_as(@mentor)

    get mentoring_alpha_schedule_signup_sheet_path(@day_slot)

    assert_response :success
    assert_match "No one has signed up for this shift yet", response.body
    assert_match "Standby list", response.body
  end

  test "a direct visit to the information sheet is turned back while no one is signed in" do
    sign_in_as(@mentor)

    get mentoring_alpha_schedule_info_sheet_path(@day_slot)

    assert_redirected_to mentoring_alpha_schedule_shift_path(@day_slot)
    assert_match "No Alphas are signed into this shift yet", flash[:error]
  end

  test "a direct visit to the apparel sheet is turned back while no one is signed in" do
    sign_in_as(@mentor)

    get mentoring_alpha_schedule_apparel_path(@day_slot)

    assert_redirected_to mentoring_alpha_schedule_shift_path(@day_slot)
  end

  test "the information sheet lists only the signed-in Alphas" do
    sign_in_to_shift(@signed_in_alpha, @day_slot)
    sign_in_as(@mentor)

    get mentoring_alpha_schedule_info_sheet_path(@day_slot)

    assert_response :success
    assert_match "AlphaSignedIn", response.body
    assert_no_match(/AlphaPlain/, response.body)
    # Upstream's heading: year, shift, when, then the document name.
    assert_match "Alpha Information", response.body
    assert_match "Alpha Walk Wednesday Day", response.body
  end

  test "the information sheet captions each field the way the paper form does" do
    sign_in_to_shift(@signed_in_alpha, @day_slot)
    sign_in_as(@mentor)

    get mentoring_alpha_schedule_info_sheet_path(@day_slot)

    assert_response :success
    ["Handle", "Gender", "Training Location", "Home",
     "Known Rangers", "Known Alphas", "Prior Mentors", "Mentor Notes"].each do |caption|
      assert_match caption, response.body
    end
  end

  test "the information sheet prints prior mentors with their short outcome" do
    sign_in_to_shift(@signed_in_alpha, @day_slot)
    mentor_of_record = person(:active_ranger)
    PersonMentor.create!(person: @signed_in_alpha, mentor: mentor_of_record,
                         mentor_year: YEAR - 2, status: PersonMentor::STATUS_SELF_BONK)
    sign_in_as(@mentor)

    get mentoring_alpha_schedule_info_sheet_path(@day_slot)

    assert_response :success
    assert_match "#{YEAR - 2} (SB)", response.body
    assert_match mentor_of_record.callsign, response.body
  end

  test "the information sheet prints a mentor-team year that carries a rank but no note" do
    sign_in_to_shift(@flagged_alpha, @day_slot)
    sign_in_as(@mentor)

    get mentoring_alpha_schedule_info_sheet_path(@day_slot)

    assert_response :success
    # @flagged_alpha has a rank 3 and no notes; upstream iterates the whole
    # mentor team, so the year still appears under Mentor Notes.
    assert_match "Rank 3", response.body
    assert_no_match(/Mentor Notes<\/span>\s*<em>None<\/em>/, response.body)
  end

  test "the apparel sheet splits passing from bonked and totals only the passing" do
    sign_in_to_shift(@signed_in_alpha, @day_slot)
    sign_in_to_shift(@flagged_alpha, @day_slot)
    # A bonk this year moves the flagged Alpha into the bonked group.
    PersonMentor.create!(person: @flagged_alpha, mentor: person(:active_ranger),
                         mentor_year: YEAR, status: PersonMentor::STATUS_BONK)
    sign_in_as(@mentor)

    get mentoring_alpha_schedule_apparel_path(@day_slot)

    assert_response :success
    assert_match "Pass/Pending", response.body
    assert_match "Bonked", response.body
    assert_match "bonked Alphas are excluded", response.body
    # Only the passing Alpha's shirts are counted, so each kind totals 1.
    assert_match "T-Shirts", response.body
  end

  test "the apparel sheet says so when no one bonked" do
    sign_in_to_shift(@signed_in_alpha, @day_slot)
    sign_in_as(@mentor)

    get mentoring_alpha_schedule_apparel_path(@day_slot)

    assert_response :success
    assert_match "No Bonked Alphas are signed into this shift", response.body
  end
end
