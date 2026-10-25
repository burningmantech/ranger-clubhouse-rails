# frozen_string_literal: true

require "test_helper"

# Training > All Trainee Notes: the ART-only gate, the two upstream grouping
# bugs this port fixes (duplicated notes, mislabeled not-passed notes),
# standing classification, the filters, and the CSV export shape.
class Training::AllNotesControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include TrainingSlotTestHelper
  include ActiveSupport::Testing::TimeHelpers

  YEAR = 2026
  SLUG = "green-dot"

  setup do
    travel_to Time.zone.local(YEAR, 8, 10, 12, 0, 0)
    Rails.cache.clear
    Current.reset

    @dirt = Position.create!(id: Position::TRAINING, title: "Training",
                             type: Position::TYPE_TRAINING, active: true)
    @green_dot = Position.create!(id: Position::GREEN_DOT_TRAINING, title: "Green Dot Training",
                                  type: Position::TYPE_TRAINING, active: true)
    # The positions standing is computed from.
    @veteran_position = Position.create!(id: Position::DIRT_GREEN_DOT, title: "Dirt - Green Dot",
                                         type: "Frontline", active: true)
    @mentee_position = Position.create!(id: Position::GREEN_DOT_MENTEE, title: "Green Dot Mentee",
                                        type: "Frontline", active: true)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::TRAINER, "Trainer")
    ensure_role(Role::ART_TRAINER_BASE | Position::GREEN_DOT_TRAINING, "Green Dot Interface")

    @admin = person(:auditor_ranger)
    @art_trainer = person(:retired_ranger)
    @dirt_trainer = person(:echelon_ranger)

    grant_role(@admin, Role::ADMIN)
    grant_role(@art_trainer, Role::ART_TRAINER_BASE | Position::GREEN_DOT_TRAINING)
    grant_role(@dirt_trainer, Role::TRAINER)

    @session = create_slot(@green_dot, begins: Time.zone.local(YEAR, 6, 1, 9, 0, 0),
                                       description: "Grass Valley, California")
  end

  teardown do
    Current.reset
    Rails.cache.clear
    travel_back
  end

  # Sign someone up for a session and record their result.
  def enroll(person_record, slot = @session, status: TraineeStatus::STATUS_PASSED, rank: nil)
    PersonSlot.create!(person_id: person_record.id, slot_id: slot.id)
    TraineeStatus.create!(person_id: person_record.id, slot_id: slot.id, status:, rank:)
  end

  def note(person_record, slot, text, is_log: false, created_at: Time.current)
    TraineeNote.create!(person_id: person_record.id, slot_id: slot.id, note: text,
                        is_log:, person_source_id: @art_trainer.id, created_at:)
  end

  def get_report(**params)
    get training_all_notes_path(SLUG, year: YEAR, **params)
  end

  # --- authorization -------------------------------------------------------

  test "the ART's interface role grants access" do
    enroll(person(:active_ranger))

    sign_in_as(@art_trainer)
    get_report

    assert_response :success
    assert_match "All Trainee Notes", response.body
  end

  test "an admin gets access" do
    enroll(person(:active_ranger))

    sign_in_as(@admin)
    get_report

    assert_response :success
  end

  test "a plain Trainer is refused another ART's notes" do
    sign_in_as(@dirt_trainer)
    get_report

    assert_redirected_to me_root_path
  end

  test "In-Person Training has no notes report" do
    sign_in_as(@admin)
    get training_all_notes_path("in-person", year: YEAR)

    assert_redirected_to training_path("in-person", year: YEAR)
    assert_match(/ART report/, flash[:error])
  end

  # --- what lands on the list ---------------------------------------------

  test "only people marked as passed appear" do
    passed = person(:active_ranger)
    failed = person(:inactive_ranger)
    enroll(passed)
    enroll(failed, status: TraineeStatus::STATUS_NOT_PASSED)

    sign_in_as(@admin)
    get_report

    assert_response :success
    assert_match passed.callsign, response.body
    assert_no_match(/#{Regexp.escape(failed.callsign)}/, response.body)
  end

  test "a passing grade without a sign-up does not resurrect someone" do
    ghost = person(:active_ranger)
    TraineeStatus.create!(person_id: ghost.id, slot_id: @session.id, status: TraineeStatus::STATUS_PASSED)

    sign_in_as(@admin)
    get_report

    assert_response :success
    assert_no_match(/#{Regexp.escape(ghost.callsign)}/, response.body)
  end

  test "log notes are the audit trail, not trainer feedback" do
    trainee = person(:active_ranger)
    enroll(trainee)
    note(trainee, @session, "rank change [2] -> [1]", is_log: true)

    sign_in_as(@admin)
    get_report

    assert_response :success
    assert_no_match(/rank change/, response.body)
    assert_match "no notes", response.body
  end

  test "another year's sessions are not included" do
    trainee = person(:active_ranger)
    last_year = create_slot(@green_dot, begins: Time.zone.local(YEAR - 1, 6, 1, 9, 0, 0),
                                        description: "Last Year")
    enroll(trainee, last_year)
    note(trainee, last_year, "Older feedback")

    sign_in_as(@admin)
    get_report

    assert_response :success
    assert_no_match(/Older feedback/, response.body)
  end

  # --- the two upstream grouping bugs -------------------------------------

  test "notes are not duplicated when someone passes two sessions" do
    trainee = person(:active_ranger)
    second = create_slot(@green_dot, begins: Time.zone.local(YEAR, 7, 1, 9, 0, 0),
                                     description: "Fly Ranch, Nevada")
    enroll(trainee)
    enroll(trainee, second)
    note(trainee, @session, "Present and attentive throughout.")
    note(trainee, second, "Relatively new Ranger, active at Regionals.")

    sign_in_as(@admin)
    get_report

    assert_response :success
    # Upstream replays every one of a person's notes for each session they
    # passed, so each of these would appear twice.
    assert_equal 1, response.body.scan("Present and attentive throughout.").size
    assert_equal 1, response.body.scan("Relatively new Ranger, active at Regionals.").size
  end

  test "a note on a session the person did not pass keeps its own session and is labeled" do
    trainee = person(:active_ranger)
    no_show = create_slot(@green_dot, begins: Time.zone.local(YEAR, 4, 18, 9, 0, 0),
                                      description: "Zoom from Portland, Oregon")
    # Someone else passed the earlier session, which is what puts it in range.
    enroll(person(:inactive_ranger), no_show)
    enroll(trainee, no_show, status: TraineeStatus::STATUS_NO_SHOW)
    enroll(trainee, @session, rank: 2)
    note(trainee, no_show, "No Show")

    sign_in_as(@admin)
    get_report

    assert_response :success
    assert_match "No Show", response.body
    assert_match "did not pass this session", response.body

    # The note belongs to the April session, not the June one it would be
    # filed under upstream.
    rows = response.body.split("<tr")
    no_show_row = rows.find { |row| row.include?("No Show") }
    assert_includes no_show_row, "Portland"
    assert_not_includes no_show_row, "Grass Valley"
  end

  test "a not-passed session carries its own rank, not the passed session's" do
    trainee = person(:active_ranger)
    earlier = create_slot(@green_dot, begins: Time.zone.local(YEAR, 4, 18, 9, 0, 0),
                                      description: "Zoom from Portland, Oregon")
    enroll(person(:inactive_ranger), earlier)
    enroll(trainee, earlier, status: TraineeStatus::STATUS_NOT_PASSED, rank: 3)
    enroll(trainee, @session, rank: 1)
    note(trainee, earlier, "Left early.")

    sign_in_as(@admin)
    get_report

    assert_response :success
    rows = response.body.split("<tr")
    earlier_row = rows.find { |row| row.include?("Left early.") }
    assert_includes earlier_row, "Rank 3"
    assert_not_includes earlier_row, "Rank 1"
  end

  # --- standing ------------------------------------------------------------

  test "standing is veteran, mentee, or prospective" do
    veteran = person(:active_ranger)
    mentee = person(:inactive_ranger)
    prospective = person(:alpha_ranger)
    [veteran, mentee, prospective].each { |trainee| enroll(trainee) }
    PersonPosition.create!(person_id: veteran.id, position_id: @veteran_position.id)
    PersonPosition.create!(person_id: mentee.id, position_id: @mentee_position.id)

    sign_in_as(@admin)
    get_report

    assert_response :success
    rows = response.body.split("<tr")
    assert_includes rows.find { |row| row.include?(veteran.callsign) }, "veteran"
    assert_includes rows.find { |row| row.include?(mentee.callsign) }, "mentee"
    assert_includes rows.find { |row| row.include?(prospective.callsign) }, "prospective"
  end

  # --- rank ----------------------------------------------------------------

  test "the legacy rank default of zero reads as no rank" do
    trainee = person(:active_ranger)
    enroll(trainee)
    TraineeStatus.where(person_id: trainee.id, slot_id: @session.id).update_all(rank: 0)

    sign_in_as(@admin)
    get_report

    assert_response :success
    assert_no_match(/Rank 0/, response.body)
  end

  # --- filters -------------------------------------------------------------

  test "the standing filter narrows the list" do
    veteran = person(:active_ranger)
    prospective = person(:alpha_ranger)
    [veteran, prospective].each { |trainee| enroll(trainee) }
    PersonPosition.create!(person_id: veteran.id, position_id: @veteran_position.id)

    sign_in_as(@admin)
    get_report(standing: "prospective")

    assert_response :success
    assert_match prospective.callsign, response.body
    assert_no_match(/#{Regexp.escape(veteran.callsign)}/, response.body)
  end

  test "only-people-with-notes hides everyone who was never written about" do
    noted = person(:active_ranger)
    silent = person(:inactive_ranger)
    enroll(noted)
    enroll(silent)
    note(noted, @session, "Rational, insightful")

    sign_in_as(@admin)
    get_report(notes: "1")

    assert_response :success
    assert_match noted.callsign, response.body
    assert_no_match(/#{Regexp.escape(silent.callsign)}/, response.body)
  end

  test "the notes filter is off by default" do
    silent = person(:inactive_ranger)
    enroll(silent)

    sign_in_as(@admin)
    get_report

    assert_response :success
    assert_match silent.callsign, response.body
  end

  # --- CSV -----------------------------------------------------------------

  test "the CSV exports one row per session with its zone, rank, and pass state" do
    trainee = person(:active_ranger)
    PersonPosition.create!(person_id: trainee.id, position_id: @veteran_position.id)
    enroll(trainee, rank: 2)
    note(trainee, @session, "Rational, insightful")

    sign_in_as(@admin)
    get training_all_notes_path(SLUG, year: YEAR, format: :csv)

    assert_response :success
    assert_equal Training::AllNotesController::CSV_HEADER.join(","), response.body.lines.first.chomp
    # The session time is the slot's own wall clock, never converted, and its
    # zone rides along so two sessions in different zones can be compared.
    assert_match(/^#{trainee.callsign},active,veteran,#{YEAR}-06-01 09:00,PDT,"Grass Valley, California",2,Yes,"Rational, insightful"$/,
                 response.body)
  end

  test "the CSV numbers several notes on one session and ignores the filters" do
    noted = person(:active_ranger)
    silent = person(:inactive_ranger)
    enroll(noted)
    enroll(silent)
    note(noted, @session, "First impression.", created_at: 2.days.ago)
    note(noted, @session, "Second thought.", created_at: 1.day.ago)

    sign_in_as(@admin)
    get training_all_notes_path(SLUG, year: YEAR, notes: "1", format: :csv)

    assert_response :success
    assert_match "\"Note #1:\nFirst impression.\nNote #2:\nSecond thought.\n\"", response.body
    # The export is the record of the year, not the filtered page. Notes carry
    # real newlines, so records are counted by row prefix, not by line count.
    assert_equal 1, response.body.lines.count { |line| line.start_with?("#{silent.callsign},") }
  end

  # --- empty state ---------------------------------------------------------

  test "a year with no one passed says so" do
    sign_in_as(@admin)
    get_report

    assert_response :success
    assert_match(/No one has passed/, response.body)
  end
end
