# frozen_string_literal: true

require "test_helper"

# The session management page reads: authorization, the slot guard, the page
# body (alerts, trainer table, trainee cards), and the two print views.
class Training::SessionPageTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper
  include TrainingSlotTestHelper
  include TrainingSessionTestHelper
  include ActiveSupport::Testing::TimeHelpers

  setup do
    setup_training_session_world
  end

  teardown do
    teardown_training_session_world
  end

  # --- who may look ---------------------------------------------------------

  test "dirt trainers, mentors, VCs, and admins may view; outsiders may not" do
    [@admin, @dirt_trainer, @mentor].each do |viewer|
      sign_in_as(viewer)
      get dirt_session_path
      assert_response :success, "#{viewer.callsign} should view the session page"
    end

    outsider = person(:prospective_ranger)
    sign_in_as(outsider)
    get dirt_session_path
    assert_redirected_to me_root_path
  end

  test "the ART interface role views its own ART's sessions only" do
    sign_in_as(@art_trainer)

    get art_session_path
    assert_response :success

    get dirt_session_path
    assert_redirected_to me_root_path
  end

  test "a slot from another training is turned away, not crashed on" do
    sign_in_as(@admin)

    get "/training/in-person/session/#{@art_slot.id}"

    assert_redirected_to training_path("in-person")
    assert_equal "Training session not found.", flash[:error]
  end

  test "an HQ refresher slot resolves under HQ Full Training" do
    hq_full = Position.create!(id: Position::HQ_FULL_TRAINING, title: "HQ Full Training",
                               type: Position::TYPE_TRAINING, active: true)
    Position.create!(id: Position::HQ_REFRESHER_TRAINING, title: "HQ Refresher Training",
                     type: Position::TYPE_TRAINING, active: true)
    Position.create!(id: Position::HQ_TRAINER, title: "HQ Trainer",
                     type: Position::TYPE_TRAINING, active: true)
    ensure_role(Role::ART_TRAINER_BASE | Position::HQ_FULL_TRAINING, "HQ Interface")
    refresher_slot = create_slot(Position.find(Position::HQ_REFRESHER_TRAINING),
                                 begins: Time.zone.local(YEAR, 8, 9, 9, 0, 0))
    sign_in_as(@admin)

    get "/training/hq-full/session/#{refresher_slot.id}"

    assert_response :success
    assert_equal hq_full.id, Training.find_training_position("hq-full").id
  end

  # --- the page body --------------------------------------------------------

  test "the page shows alerts, the trainer table, and trainee cards" do
    trainer_slot = create_slot(@dirt_trainer_position, begins: Time.zone.local(YEAR, 8, 8, 8, 30, 0),
                               description: "Bright Eyes")
    sign_up(@dirt_trainer, trainer_slot)
    TrainerStatus.create!(person_id: @dirt_trainer.id, slot_id: @dirt_slot.id,
                          trainer_slot_id: trainer_slot.id, status: TrainerStatus::STATUS_ATTENDED,
                          is_lead: true)

    trainee = person(:prospective_ranger)
    sign_up(trainee, @dirt_slot)
    PersonFka.create!(person_id: trainee.id, fka: "Dusty Boots", fka_normalized: "dustyboots",
                      fka_soundex: "D231")
    TraineeNote.record(person_id: trainee.id, slot_id: @dirt_slot.id, note: "Great scenario energy.",
                       person_source_id: @dirt_trainer.id)

    sign_in_as(@dirt_trainer)
    get dirt_session_path

    assert_response :success
    assert_select "h1", text: /Training —/
    assert_match trainee.callsign, response.body
    assert_match "FKA Dusty Boots", response.body
    assert_match "Great scenario energy.", response.body
    assert_match "Signed up", response.body
    assert_match "Walk-ins are not allowed", response.body
    assert_select "select[name=?]", "trainers[#{trainer_slot.id}-#{@dirt_trainer.id}][status]"
    assert_match "Save Trainers", response.body
  end

  test "the page counts each trainee status and badges every card" do
    # trainee => [stored status, card badge]; the last one has no row at all.
    trainees = {
      person(:active_ranger) => [TraineeStatus::STATUS_PASSED, "Passed"],
      person(:inactive_ranger) => [TraineeStatus::STATUS_NO_SHOW, "No Show"],
      person(:retired_ranger) => [TraineeStatus::STATUS_NOT_PASSED, "Not Passed"],
      person(:auditor_ranger) => [TraineeStatus::STATUS_PENDING, "Pending"],
      person(:prospective_ranger) => [nil, "Pending"]
    }
    trainees.each do |trainee, (status, _badge)|
      sign_up(trainee, @dirt_slot)
      TraineeStatus.create!(person_id: trainee.id, slot_id: @dirt_slot.id, status:) if status
    end

    sign_in_as(@dirt_trainer)
    get dirt_session_path

    assert_response :success
    tiles = css_select("#session-stats > div > div").to_h do |tile|
      value, label = tile.element_children.map { |part| part.text.strip }
      [label, value]
    end
    assert_equal({ "Pending" => "2", "Passed" => "1", "No Show" => "1", "Not Passed" => "1" },
                 tiles.slice("Pending", "Passed", "No Show", "Not Passed"))
    trainees.each do |trainee, (_status, badge)|
      assert_select "#trainee-#{trainee.id} .badge", text: badge
    end
  end

  test "an unmatched session explains the trainer slot rule and an inactive slot warns" do
    @dirt_slot.update!(active: false)
    sign_in_as(@dirt_trainer)

    get dirt_session_path

    assert_response :success
    assert_match "No Trainer Slots Were Found", response.body
    assert_match "Session Not Activated", response.body
  end

  test "dirt mentors see the roster read-only" do
    trainee = person(:prospective_ranger)
    sign_up(trainee, @dirt_slot)
    sign_in_as(@mentor)

    get dirt_session_path

    assert_response :success
    assert_match trainee.callsign, response.body
    assert_no_match(/Score</, response.body)
    assert_no_match(/Add Person/, response.body)
  end

  test "an ART trainer reads trainee callsigns as text: person pages are closed to them" do
    trainee = person(:prospective_ranger)
    sign_up(trainee, @art_slot)

    sign_in_as(@art_trainer)
    get art_session_path
    assert_response :success
    assert_match trainee.callsign, response.body
    assert_select "a[href=?]", person_path(trainee), count: 0

    sign_in_as(@admin)
    get art_session_path
    assert_select "a[href=?]", person_path(trainee), text: trainee.callsign
  end

  test "the graduate button appears only for the ART graduate role" do
    Position.create!(id: Position::GREEN_DOT_MENTEE, title: "Green Dot Mentee", active: true)
    Position.create!(id: Position::SANCTUARY_MENTEE, title: "Sanctuary Mentee", active: true)
    Position.create!(id: Position::DIRT_GREEN_DOT, title: "Dirt - Green Dot", active: true)
    sign_up(person(:prospective_ranger), @art_slot)

    sign_in_as(@art_trainer)
    get art_session_path
    assert_response :success
    assert_no_match(/Graduate Trainees/, response.body)

    grant_role(@art_trainer, Role::ART_GRADUATE_BASE | Position::GREEN_DOT_TRAINING)
    sign_in_as(@art_trainer)
    get art_session_path
    assert_match(/Graduate Trainees/, response.body)
    assert_match(/Work History/, response.body)
  end

  # --- the landing link -----------------------------------------------------

  test "the landing page session time links to the management page" do
    sign_in_as(@dirt_trainer)

    get training_path("in-person")

    assert_response :success
    assert_select "a[href=?]", dirt_session_path
  end

  # --- print views ----------------------------------------------------------

  test "the sign-up sheet lets the browser paginate and adds walk-ins for ARTs only" do
    trainee = person(:prospective_ranger)
    sign_up(trainee, @dirt_slot)
    sign_in_as(@dirt_trainer)

    get dirt_session_path("signup-sheet")
    assert_response :success
    assert_match trainee.callsign, response.body
    assert_select "th", "Signature"
    assert_select "tbody .signup-notes-cell", minimum: 1
    assert_no_match(/Walk-ins/, response.body)

    # One table, paginated by the browser: no server-side page slicing, the
    # repeating running head names the session on a continuation sheet, and
    # the page numbers come from the named @page rule's margin box.
    assert_select "table", count: 1
    assert_select ".signup-running-head th", count: 1
    assert_no_match(/Page \d+ of \d+/, response.body)
    assert_match "@page signup-sheet", response.body
    assert_match 'content: "Page " counter(page) " of " counter(pages)', response.body

    art_trainee = person(:auditor_ranger)
    sign_up(art_trainee, @art_slot)
    sign_in_as(@art_trainer)

    get art_session_path("signup-sheet")
    assert_response :success
    assert_match(/Walk-ins/, response.body)
    assert_select ".signup-running-head th", count: 2
  end

  test "an empty ART sign-up sheet still heads both its sections" do
    sign_in_as(@art_trainer)

    get art_session_path("signup-sheet")

    assert_response :success
    assert_match "No one is signed up for this session yet.", response.body
    # The empty state used to print a server-computed "Page 1 of 1" across two
    # physical sheets; both sections now head themselves, and the page numbers
    # are counted by the browser.
    assert_no_match(/Page \d+ of \d+/, response.body)
    assert_select ".signup-doc-label", text: /Walk-ins/
    assert_select ".signup-running-head th", count: 1
  end

  test "the trainer's report bands the dirt roster with tiles, callout, and legend" do
    status_time = Time.zone.local(YEAR, 1, 1, 0, 0, 0)
    vet = person(:echelon_ranger)
    vet.update!(years_as_ranger: [2023, 2024])
    PersonStatus.create!(person_id: vet.id, old_status: "prospective", new_status: "active",
                         created_at: status_time)
    TraineeStatus.create!(person_id: vet.id, slot_id: @dirt_slot.id, status: TraineeStatus::STATUS_PASSED)

    inactive_vet = person(:inactive_ranger)
    inactive_vet.update!(years_as_ranger: [2020, 2021, 2022, 2023])
    PersonStatus.create!(person_id: inactive_vet.id, old_status: "active", new_status: "inactive",
                         created_at: status_time)

    binary = person(:active_ranger)
    binary.update!(years_as_ranger: [2025])
    PersonStatus.create!(person_id: binary.id, old_status: "prospective", new_status: "active",
                         created_at: status_time)

    prospective = person(:prospective_ranger)
    PersonStatus.create!(person_id: prospective.id, old_status: "auditor", new_status: "prospective",
                         created_at: status_time)

    [vet, inactive_vet, binary, prospective].each { |p| sign_up(p, @dirt_slot) }
    Position.create!(id: Position::GREEN_DOT_LEAD, title: "Green Dot Lead", short_title: "GDL",
                     on_trainer_report: true, active: true)
    PersonPosition.create!(person_id: vet.id, position_id: Position::GREEN_DOT_LEAD)

    sign_in_as(@dirt_trainer)
    get dirt_session_path("trainers-report")

    assert_response :success
    body = response.body

    # Bands in order with counts; the empty Auditors band still prints.
    assert_select ".report-band td", text: "Veterans (2)"
    assert_select ".report-band td", text: "Binaries (1)"
    assert_select ".report-band td", text: "Prospectives (1)"
    assert_select ".report-band td", text: "Auditors (0)"
    assert_select ".report-empty-row td", text: "None signed up."
    assert_operator body.index("Veterans (2)"), :<, body.index("Binaries (1)")
    assert_operator body.index("Binaries (1)"), :<, body.index("Prospectives (1)")
    assert_operator body.index("Prospectives (1)"), :<, body.index("Auditors (0)")
    # Anchor past the band header -- the callout above the table also names
    # InactiveRanger, which would satisfy a whole-body comparison vacuously.
    veterans_rows = body[body.index("Veterans (2)")..]
    assert_operator veterans_rows.index("InactiveRanger"), :<, veterans_rows.index("EchelonTest"),
                    "years sort descending inside the Veterans band"

    # Glance line: the pass cell sits right before the callsign cell; unscored
    # rows get a blank checkbox while the scored veteran shows Y.
    assert_select ".report-id-row .report-pass + .report-callsign", count: 4
    assert_select ".report-pass .report-checkbox", count: 3
    assert_select ".report-id-row .report-pass", text: "Y", count: 1
    assert_select ".report-years-pill", text: "4 yrs"
    assert_select ".report-years-pill", text: "1 yr"
    assert_select ".report-years-pill.report-new", text: "NEW", count: 1

    # Full-day flag for the inactive veteran; status chips only where the band
    # does not already say it (no "prospective" chip inside Prospectives).
    assert_select ".report-full-day", text: "Full day required", count: 1
    assert_select ".report-status", count: 1
    assert_select ".report-status", text: "inactive"

    # The callout lists callsigns only; emails stay on the detail lines.
    assert_select ".report-callout", text: /InactiveRanger/
    assert_select ".report-callout", text: /@/, count: 0
    assert_match "inactive@example.com", body

    # Stat tiles agree with the bands.
    assert_select ".report-stat", text: "4/20 Signed up"
    assert_select ".report-stat", text: "2 Veterans"
    assert_select ".report-stat", text: "1 Binaries"
    assert_select ".report-stat", text: "1 Prospective"
    assert_select ".report-stat", text: "0 Auditors"
    assert_select ".report-stat", text: "1 Inact/Retired"
    assert_select ".report-stat", text: "0 Trainers"

    # Teams chip + legend, and the named @page rule carrying the footer.
    assert_select ".report-chip", text: "GDL"
    assert_select ".report-legend-cols div", text: "GDL Green Dot Lead"
    assert_match "@page trainers-report", body
  end

  test "the trainer's report marks each result and keeps the tick box for the undecided" do
    sign_up(person(:prospective_ranger), @dirt_slot)
    sign_in_as(@dirt_trainer)

    get dirt_session_path("trainers-report")
    assert_no_match "NS no show", response.body, "no legend until someone has a mark"

    {
      person(:active_ranger) => TraineeStatus::STATUS_PASSED,
      person(:inactive_ranger) => TraineeStatus::STATUS_NOT_PASSED,
      person(:retired_ranger) => TraineeStatus::STATUS_NO_SHOW,
      person(:auditor_ranger) => TraineeStatus::STATUS_PENDING
    }.each do |trainee, status|
      sign_up(trainee, @dirt_slot)
      TraineeStatus.create!(person_id: trainee.id, slot_id: @dirt_slot.id, status:)
    end

    get dirt_session_path("trainers-report")

    assert_response :success
    %w[Y N NS].each { |mark| assert_select ".report-id-row .report-pass", text: mark, count: 1 }
    assert_select ".report-pass .report-checkbox", count: 2
    assert_match "Y passed · N not passed · NS no show", response.body
  end

  test "an ART report bands veterans, ART prospectives, and auditors without the dirt callout" do
    Position.create!(id: Position::DIRT_GREEN_DOT, title: "Dirt - Green Dot", active: true,
                     training_position_id: Position::GREEN_DOT_TRAINING)
    status_time = Time.zone.local(YEAR, 1, 1, 0, 0, 0)

    art_vet = person(:echelon_ranger)
    art_vet.update!(years_as_ranger: [2021, 2022, 2023])
    PersonPosition.create!(person_id: art_vet.id, position_id: Position::DIRT_GREEN_DOT)
    PersonStatus.create!(person_id: art_vet.id, old_status: "active", new_status: "inactive",
                         created_at: status_time)

    art_prospective = person(:prospective_ranger)

    auditor = person(:auditor_ranger)
    PersonPosition.create!(person_id: auditor.id, position_id: Position::DIRT_GREEN_DOT)
    PersonStatus.create!(person_id: auditor.id, old_status: "active", new_status: "auditor",
                         created_at: status_time)

    [art_vet, art_prospective, auditor].each { |p| sign_up(p, @art_slot) }

    sign_in_as(@art_trainer)
    get art_session_path("trainers-report")

    assert_response :success
    assert_select ".report-band td", text: "Veterans (1)"
    assert_select ".report-band td", text: "ART Prospectives (1)"
    assert_select ".report-band td", text: "Auditors (1)"
    assert_select ".report-band td", text: "Binaries (0)", count: 0
    assert_select ".report-band td", text: "Prospectives (1)", count: 0

    # No dirt callout and no full-day flags on an ART session; the Auditors
    # band suppresses its own chip while the inactive veteran keeps one.
    assert_select ".report-callout", count: 0
    assert_select ".report-full-day", count: 0
    assert_select ".report-status", text: "auditor", count: 0
    assert_select ".report-status", text: "inactive", count: 1

    # ART tile row: no Binaries/Prospective tiles.
    assert_select ".report-stat", text: "3/20 Signed up"
    assert_select ".report-stat", text: "1 Veterans"
    assert_select ".report-stat", text: "1 ART Prospectives"
    assert_select ".report-stat", text: "1 Auditors"
    assert_select ".report-stat", text: "1 Inact/Retired"
    assert_select ".report-stat", text: "0 Trainers"
    assert_select ".report-stat", text: /Binaries/, count: 0
  end

  test "an ART auditor holding no trained position bands under Auditors, not ART Prospectives" do
    # Holding no position trained by this ART flags the auditor as an ART
    # prospective too -- auditor status must win the band.
    Position.create!(id: Position::DIRT_GREEN_DOT, title: "Dirt - Green Dot", active: true,
                     training_position_id: Position::GREEN_DOT_TRAINING)
    auditor = person(:auditor_ranger)
    PersonStatus.create!(person_id: auditor.id, old_status: "active", new_status: "auditor",
                         created_at: Time.zone.local(YEAR, 1, 1, 0, 0, 0))
    sign_up(auditor, @art_slot)

    sign_in_as(@art_trainer)
    get art_session_path("trainers-report")

    assert_response :success
    assert_select ".report-band td", text: "Auditors (1)"
    assert_select ".report-band td", text: "ART Prospectives (0)"
    assert_select ".report-band td", text: "Veterans (0)"
  end
end
