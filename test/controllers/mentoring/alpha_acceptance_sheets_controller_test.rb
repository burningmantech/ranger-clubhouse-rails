# frozen_string_literal: true

require "test_helper"

class Mentoring::AlphaAcceptanceSheetsControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include BulkSelectTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include TrainingSlotTestHelper
  include PersonTestFactory
  include ActiveSupport::Testing::TimeHelpers

  YEAR = 2026
  DENY_MESSAGE = "Admin or Mentor role required to print Alpha acceptance sheets."

  setup do
    travel_to Time.zone.local(YEAR, 8, 25, 12, 0, 0)
    Rails.cache.clear
    Current.reset

    @alpha_position = Position.create!(id: Position::ALPHA, title: "Alpha",
                                       type: Position::TYPE_FRONTLINE, active: true)
    @training_position = Position.create!(id: Position::TRAINING, title: "In-Person Training",
                                          type: Position::TYPE_TRAINING, active: true)

    @day_slot = create_slot(@alpha_position, begins: Time.zone.local(YEAR, 8, 26, 8, 0, 0),
                            ends: Time.zone.local(YEAR, 8, 26, 18, 0, 0),
                            description: "Alpha Walk Wednesday Day")
    @swing_slot = create_slot(@alpha_position, begins: Time.zone.local(YEAR, 8, 26, 14, 0, 0),
                              ends: Time.zone.local(YEAR, 8, 26, 23, 0, 0),
                              description: "Alpha Walk Wednesday Swing")

    @training_slot = create_slot(@training_position, begins: Time.zone.local(YEAR, 6, 14, 9, 0, 0),
                                 description: "Bay Area - Berkeley")
    @old_training_slot = create_slot(@training_position, begins: Time.zone.local(YEAR - 1, 6, 14, 9, 0, 0),
                                     description: "Bay Area - Last Year")

    # Ready: passed this year's training, signed up for the Day shift.
    @ready = create_person("AReady", status: Person::ALPHA)
    sign_up_for_training(@ready, @training_slot, status: TraineeStatus::STATUS_PASSED, rank: Intake::ABOVE_AVERAGE,
                         feedback_delivered: true)
    PersonSlot.create!(person_id: @ready.id, slot_id: @day_slot.id)

    # No training sign-up at all, and therefore not trained either.
    @untrained = create_person("BUntrained", status: Person::ALPHA)
    PersonSlot.create!(person_id: @untrained.id, slot_id: @swing_slot.id)

    # Signed up for training but did not pass, and no Alpha shift.
    @failed = create_person("CFailed", status: Person::ALPHA)
    sign_up_for_training(@failed, @training_slot, status: TraineeStatus::STATUS_NOT_PASSED)

    # Passed -- but LAST year, so this year's verdict is still "not trained".
    @stale = create_person("DStale", status: Person::ALPHA)
    sign_up_for_training(@stale, @old_training_slot, status: TraineeStatus::STATUS_PASSED)
    PersonSlot.create!(person_id: @stale.id, slot_id: @day_slot.id)

    # Not an Alpha: must never appear on the page or print a form.
    @prospective = create_person("EProspective", status: Person::PROSPECTIVE)
    PersonSlot.create!(person_id: @prospective.id, slot_id: @day_slot.id)

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

  # The fixtures carry an Alpha of their own, so roster assertions name the
  # people this test made rather than the whole list.
  def my_row_ids
    mine = [@ready, @untrained, @failed, @stale].map { |person| "acceptance-row-#{person.id}" }
    css_select("tbody tr").map { |row| row["id"] }.compact & mine
  end

  # Rendered HTML wraps freely; a caption and its value can land on separate
  # lines and still read as one line on paper.
  def squished_body
    response.body.squish
  end

  def sign_up_for_training(person, slot, status:, rank: nil, feedback_delivered: false)
    PersonSlot.create!(person_id: person.id, slot_id: slot.id)
    TraineeStatus.create!(person_id: person.id, slot_id: slot.id, status:,
                          rank:, feedback_delivered:)
  end

  # --- authorization ---

  test "an admin can view the picker" do
    sign_in_as(@admin)
    get mentoring_alpha_acceptance_sheets_path
    assert_response :success
  end

  test "a mentor can view the picker" do
    sign_in_as(@mentor)
    get mentoring_alpha_acceptance_sheets_path
    assert_response :success
  end

  test "a role outside the gate is turned away" do
    sign_in_as(@outsider)
    get mentoring_alpha_acceptance_sheets_path
    assert_redirected_to me_root_path
    assert_equal DENY_MESSAGE, flash[:error]
  end

  test "the gate also covers printing" do
    sign_in_as(@outsider)
    get mentoring_alpha_acceptance_sheets_print_path(person_ids: [@ready.id])
    assert_redirected_to me_root_path
  end

  # --- the roster ---

  test "the picker lists every current Alpha and no one else" do
    sign_in_as(@admin)
    get mentoring_alpha_acceptance_sheets_path

    assert_select "#acceptance-row-#{@ready.id}"
    assert_select "#acceptance-row-#{@untrained.id}"
    assert_select "#acceptance-row-#{@failed.id}"
    assert_select "#acceptance-row-#{@stale.id}"
    assert_select "#acceptance-row-#{@prospective.id}", false,
                  "a Prospective is not an Alpha and must not be listed"
  end

  test "rows are ordered by callsign" do
    sign_in_as(@admin)
    get mentoring_alpha_acceptance_sheets_path

    assert_equal ["acceptance-row-#{@ready.id}", "acceptance-row-#{@untrained.id}",
                  "acceptance-row-#{@failed.id}", "acceptance-row-#{@stale.id}"],
                 my_row_ids
  end

  test "every row starts selected, issues and all" do
    sign_in_as(@admin)
    get mentoring_alpha_acceptance_sheets_path

    [@ready, @untrained, @failed, @stale].each do |person|
      assert_select "input#acceptance-check-#{person.id}[checked]", 1,
                    "#{person.callsign} should start selected"
    end
    assert_bulk_select_count_matches_ticked
  end

  test "a print button sits above and below the table" do
    sign_in_as(@admin)
    get mentoring_alpha_acceptance_sheets_path
    assert_select "input[type=submit][value='Print Selected']", 2
  end

  # --- the issues column ---

  test "an Alpha with nothing outstanding shows no issues" do
    sign_in_as(@admin)
    get mentoring_alpha_acceptance_sheets_path

    row = css_select("#acceptance-row-#{@ready.id}").first.to_s
    assert_no_match(/No training sign-ups|Did not pass training|No mentor shift/, row)
  end

  test "an Alpha with no training sign-up reports both training issues" do
    sign_in_as(@admin)
    get mentoring_alpha_acceptance_sheets_path

    row = css_select("#acceptance-row-#{@untrained.id}").first.to_s
    assert_match "No training sign-ups", row
    assert_match "Did not pass training", row
    assert_no_match(/No mentor shift/, row)
  end

  test "an Alpha with no Alpha shift reports it" do
    sign_in_as(@admin)
    get mentoring_alpha_acceptance_sheets_path

    row = css_select("#acceptance-row-#{@failed.id}").first.to_s
    assert_match "Did not pass training", row
    assert_match "No mentor shift", row
    assert_no_match(/No training sign-ups/, row)
  end

  test "a pass in an earlier year does not count as trained this year" do
    sign_in_as(@admin)
    get mentoring_alpha_acceptance_sheets_path

    row = css_select("#acceptance-row-#{@stale.id}").first.to_s
    assert_match "Did not pass training", row
    assert_no_match(/No training sign-ups/, row, "the earlier session is still a sign-up")
  end

  # --- filters ---

  test "the shift filter narrows to one Alpha shift" do
    sign_in_as(@admin)
    get mentoring_alpha_acceptance_sheets_path(shift: @swing_slot.id)

    assert_select "#acceptance-row-#{@untrained.id}"
    assert_select "#acceptance-row-#{@ready.id}", false
    assert_select "#acceptance-row-#{@stale.id}", false
  end

  test "the shift filter finds Alphas signed up to no shift" do
    sign_in_as(@admin)
    get mentoring_alpha_acceptance_sheets_path(shift: "none")

    assert_select "#acceptance-row-#{@failed.id}"
    assert_select "#acceptance-row-#{@ready.id}", false
  end

  test "the issues filter shows only Alphas needing attention" do
    sign_in_as(@admin)
    get mentoring_alpha_acceptance_sheets_path(issues: "with")

    assert_select "#acceptance-row-#{@untrained.id}"
    assert_select "#acceptance-row-#{@failed.id}"
    assert_select "#acceptance-row-#{@stale.id}"
    assert_select "#acceptance-row-#{@ready.id}", false
  end

  test "the issues filter shows only Alphas ready to print" do
    sign_in_as(@admin)
    get mentoring_alpha_acceptance_sheets_path(issues: "without")

    assert_select "#acceptance-row-#{@ready.id}"
    assert_select "#acceptance-row-#{@untrained.id}", false
  end

  test "the two filters combine" do
    sign_in_as(@admin)
    get mentoring_alpha_acceptance_sheets_path(shift: @day_slot.id, issues: "with")

    assert_select "#acceptance-row-#{@stale.id}"
    assert_select "#acceptance-row-#{@ready.id}", false
    assert_select "#acceptance-row-#{@untrained.id}", false
  end

  test "a filter matching no one says so instead of showing an empty table" do
    sign_in_as(@admin)
    get mentoring_alpha_acceptance_sheets_path(shift: @swing_slot.id, issues: "without")

    assert_select "tbody tr", false
    assert_match "No Alphas matched those filters", response.body
  end

  test "the stat boxes count the whole roster, not the filtered rows" do
    total = Person.where(status: Person::ALPHA).count
    sign_in_as(@admin)
    get mentoring_alpha_acceptance_sheets_path(issues: "without")

    assert_equal 1, my_row_ids.size
    assert_match "of #{total} Alphas", response.body
    assert_match "Need Attention", response.body
  end

  # --- printing ---

  test "printing renders one form per selected Alpha" do
    sign_in_as(@admin)
    get mentoring_alpha_acceptance_sheets_print_path(person_ids: [@ready.id, @failed.id])

    assert_response :success
    assert_select "section.acceptance-sheet", 2
    assert_match "(1 / 2)", response.body
    assert_match "(2 / 2)", response.body
  end

  test "printing uses the chrome-free print layout" do
    sign_in_as(@admin)
    get mentoring_alpha_acceptance_sheets_print_path(person_ids: [@ready.id])

    assert_select "nav", false, "the print layout carries no navigation"
    assert_select "section.acceptance-sheet[data-theme=light]"
  end

  test "printing drops ids that are not current Alphas" do
    sign_in_as(@admin)
    get mentoring_alpha_acceptance_sheets_print_path(person_ids: [@ready.id, @prospective.id])

    assert_select "section.acceptance-sheet", 1
    assert_no_match(/#{@prospective.callsign}/, response.body)
  end

  test "printing no one redirects with a message instead of an empty document" do
    sign_in_as(@admin)
    get mentoring_alpha_acceptance_sheets_print_path

    assert_redirected_to mentoring_alpha_acceptance_sheets_path(shift: "all", issues: "all")
    assert_match "Pick at least one Alpha", flash[:error]
  end

  test "printing only ids outside the roster redirects too" do
    sign_in_as(@admin)
    get mentoring_alpha_acceptance_sheets_print_path(person_ids: [@prospective.id])

    assert_redirected_to mentoring_alpha_acceptance_sheets_path(shift: "all", issues: "all")
  end

  # to_i read "#{id}x" as the id and printed that Alpha's form.
  test "printing ids that are not ids prints no one" do
    sign_in_as(@admin)
    get mentoring_alpha_acceptance_sheets_print_path(person_ids: ["", "abc", "#{@ready.id}x"])

    assert_redirected_to mentoring_alpha_acceptance_sheets_path(shift: "all", issues: "all")
    assert_match "Pick at least one Alpha", flash[:error]
  end

  test "the printed form links back to the filtered picker it came from" do
    sign_in_as(@admin)
    get mentoring_alpha_acceptance_sheets_print_path(person_ids: [@ready.id],
                                                     shift: @day_slot.id.to_s, issues: "without")

    assert_select "a[href=?]",
                  mentoring_alpha_acceptance_sheets_path(shift: @day_slot.id.to_s, issues: "without")
  end

  # --- the printed form's content ---

  test "the form prints the identity block" do
    @ready.update!(pronouns: "neutral")
    PersonFka.create!(person_id: @ready.id, fka: "OldHandle", fka_normalized: "oldhandle",
                      fka_soundex: "O430")
    sign_in_as(@admin)
    get mentoring_alpha_acceptance_sheets_print_path(person_ids: [@ready.id])

    assert_match "#{YEAR} Alpha To Dirt Ranger Acceptance Form", response.body
    assert_match "Clubhouse Record # #{@ready.id}", response.body
    assert_match @ready.callsign, response.body
    assert_match "They / Them / Their", squished_body
    assert_match "FKA: OldHandle", squished_body
    assert_match "Bay Area - Berkeley", response.body
    assert_match "Alpha Walk Wednesday Day", response.body
  end

  test "an Alpha without pronouns on file is marked as such" do
    sign_in_as(@admin)
    get mentoring_alpha_acceptance_sheets_print_path(person_ids: [@ready.id])
    assert_match "(Pronouns not stated)", response.body
  end

  test "an Alpha with no approved photo gets the placeholder" do
    sign_in_as(@admin)
    get mentoring_alpha_acceptance_sheets_print_path(person_ids: [@ready.id])

    assert_match "No approved photo", response.body
    assert_select "div.acceptance-headshot img", false
  end

  test "an approved headshot prints in place of the placeholder" do
    photo = PersonPhoto.create!(person: @ready, status: PersonPhoto::APPROVED,
                                image_filename: "", orig_filename: "", profile_filename: "p.jpg")
    photo.profile.attach(io: StringIO.new("not-really-a-jpeg"), filename: "p.jpg",
                         content_type: "image/jpeg")
    sign_in_as(@admin)
    get mentoring_alpha_acceptance_sheets_print_path(person_ids: [@ready.id])

    assert_select "div.acceptance-headshot img"
    assert_no_match(/No approved photo/, response.body)
  end

  test "empty fields print a writing rule instead of nothing" do
    sign_in_as(@admin)
    get mentoring_alpha_acceptance_sheets_print_path(person_ids: [@failed.id])

    # Actual Shift, Pass/Bonk, Known Rangers, Known PNVs, and this person's
    # missing Alpha shift all print a rule to write on.
    assert_select "div.acceptance-blank", minimum: 5
  end

  test "the form prints the mentor sign-off table and its legend" do
    sign_in_as(@admin)
    get mentoring_alpha_acceptance_sheets_print_path(person_ids: [@ready.id])

    assert_select "table.acceptance-signoff tbody tr td.acceptance-signoff-rule", 12
    assert_match "#{YEAR} MENTOR NAME", response.body
    assert_match "ACCEPT W/RESERV.", response.body
    assert_match "REJECT", response.body
    assert_match "Asked to return", response.body
    assert_match "Discourage from returning", response.body
  end

  test "the form prints VC notes with their rank" do
    PersonIntake.create!(person_id: @ready.id, year: YEAR, vc_rank: Intake::ABOVE_AVERAGE)
    PersonIntakeNote.create!(person_source_id: @admin.id, person_id: @ready.id, year: YEAR, type: "vc",
                             note: "Great at orientation.", is_log: false)
    PersonIntakeNote.create!(person_source_id: @admin.id, person_id: @ready.id, year: YEAR, type: "vc",
                             note: "rank changed to 1", is_log: true)
    sign_in_as(@admin)
    get mentoring_alpha_acceptance_sheets_print_path(person_ids: [@ready.id])

    assert_match "Great at orientation.", response.body
    assert_match "Rank 1/Green", response.body
    assert_no_match(/rank changed to 1/, response.body,
                    "log notes are audit entries, not sheet content")
  end

  test "an Alpha with no VC notes says so" do
    sign_in_as(@admin)
    get mentoring_alpha_acceptance_sheets_print_path(person_ids: [@ready.id])
    assert_match "No VC notes", response.body
  end

  test "the form prints mentor notes and prior mentors" do
    mentor_person = create_person("Moonbeam")
    PersonMentor.create!(person_id: @ready.id, mentor_id: mentor_person.id,
                         mentor_year: YEAR - 2, status: PersonMentor::STATUS_SELF_BONK)
    PersonIntake.create!(person_id: @ready.id, year: YEAR - 2, mentor_rank: Intake::BELOW_AVERAGE)
    PersonIntakeNote.create!(person_source_id: @admin.id, person_id: @ready.id, year: YEAR - 2, type: "mentor",
                             note: "Left mid-shift.", is_log: false)
    sign_in_as(@admin)
    get mentoring_alpha_acceptance_sheets_print_path(person_ids: [@ready.id])

    assert_match "#{YEAR - 2} (SB) Moonbeam", squished_body
    assert_match "Left mid-shift.", response.body
    assert_match "Rank 3/Yellow", response.body
  end

  test "an Alpha never mentored before says so" do
    sign_in_as(@admin)
    get mentoring_alpha_acceptance_sheets_print_path(person_ids: [@ready.id])
    assert_match "No prior mentor notes", response.body
  end

  test "the training notes box covers passed sessions only" do
    TraineeNote.create!(person_id: @ready.id, slot_id: @training_slot.id,
                        note: "Solid on radio protocol.", is_log: false)
    TraineeNote.create!(person_id: @ready.id, slot_id: @training_slot.id,
                        note: "rank set", is_log: true)
    TraineeNote.create!(person_id: @failed.id, slot_id: @training_slot.id,
                        note: "Struggled with the scenarios.", is_log: false)
    sign_in_as(@admin)
    get mentoring_alpha_acceptance_sheets_print_path(person_ids: [@ready.id, @failed.id])

    assert_match "Solid on radio protocol.", response.body
    assert_no_match(/rank set/, response.body)
    assert_no_match(/Struggled with the scenarios/, response.body,
                    "an unpassed session's notes stay off the acceptance form")
  end

  test "a passed session with no notes says so" do
    sign_in_as(@admin)
    get mentoring_alpha_acceptance_sheets_print_path(person_ids: [@ready.id])
    assert_match "No notes given.", response.body
  end

  test "undelivered training feedback is called out" do
    other = create_person("FNoFeedback", status: Person::ALPHA)
    sign_up_for_training(other, @training_slot, status: TraineeStatus::STATUS_PASSED, feedback_delivered: false)
    sign_in_as(@admin)
    get mentoring_alpha_acceptance_sheets_print_path(person_ids: [other.id])

    assert_match "FEEDBACK NOT DELIVERED", response.body
    assert_select "span.acceptance-alert"
  end

  test "delivered training feedback is noted plainly" do
    sign_in_as(@admin)
    get mentoring_alpha_acceptance_sheets_print_path(person_ids: [@ready.id])

    assert_match "feedback delivered", response.body
    assert_select "span.acceptance-alert", false
  end
end
