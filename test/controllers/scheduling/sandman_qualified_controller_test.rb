# frozen_string_literal: true

require "test_helper"

# The Sandman Qualifications report: its gate, the four answers it gives about
# each sandman, the ways of narrowing the list, and the export.
class Scheduling::SandmanQualifiedControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include TrainingSlotTestHelper   # create_slot
  include PersonTestFactory        # create_person
  include DomIdTestHelper          # assert_unique_dom_ids

  # A year the fixtures leave alone.
  YEAR = 2022
  # Five years back, the earliest that still counts as experience.
  CUTOFF_YEAR = YEAR - Position::SANDMAN_YEAR_CUTOFF
  DENY_MESSAGE = "Admin or Event Management role required " \
                 "to view the sandman qualifications report."

  setup do
    Rails.cache.clear
    Current.reset

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::EVENT_MANAGEMENT, "Event Management")
    ensure_role(Role::EDIT_SLOTS, "Edit Slots")
    ensure_role(Role::VC, "Volunteer Coordinator")

    @admin = person(:active_ranger)
    @event_manager = person(:echelon_ranger)
    @outsider = person(:inactive_ranger)
    grant_role(@admin, Role::ADMIN)
    grant_role(@event_manager, Role::EVENT_MANAGEMENT)
    grant_role(@outsider, Role::VC)

    @sandman = Position.create!(id: Position::SANDMAN, title: "Sandman", active: true)
    @sandman_training = Position.create!(id: Position::SANDMAN_TRAINING,
                                         title: "Sandman Training",
                                         type: Position::TYPE_TRAINING, active: true)
    @sandman_trainer = Position.create!(id: Position::SANDMAN_TRAINER,
                                        title: "Sandman Trainer",
                                        type: Position::TYPE_TRAINING, active: true)
    @burn_perimeter = Position.create!(id: Position::BURN_PERIMETER,
                                       title: "Burn Perimeter", active: true)

    # The report asks the Clubhouse which checks to apply, so every test says
    # what it is assuming rather than inheriting whatever the row holds.
    set_setting(Setting::SANDMAN_REQUIRE_AFFIDAVIT, "true")
    set_setting(Setting::SANDMAN_REQUIRE_PERIMETER_EXP_WITHIN_YEARS,
                Position::SANDMAN_YEAR_CUTOFF.to_s)

    sign_in_as(@admin)
  end

  def set_setting(name, value)
    Setting.find_or_initialize_by(name:).update!(value:)
  end

  teardown do
    Current.reset
    Rails.cache.clear
  end

  def august(day, hour = 12, year: YEAR)
    Time.zone.local(year, 8, day, hour, 0, 0)
  end

  # A sandman: an active person holding the position, and nothing else yet.
  def sandperson(callsign, status: Person::ACTIVE)
    person = create_person(callsign, status:)
    PersonPosition.create!(person:, position: @sandman)
    person
  end

  # Passing this year's training.
  def train(person, year: YEAR, status: TraineeStatus::STATUS_PASSED, active: true)
    slot = create_slot(@sandman_training, begins: august(20, year:),
                       ends: august(20, 18, year:), active:)
    TraineeStatus.create!(person:, slot:, status:)
    slot
  end

  # Teaching this year's training instead of sitting it.
  def teach(person, year: YEAR, status: TrainerStatus::STATUS_ATTENDED, granted: true)
    PersonPosition.create!(person:, position: @sandman_trainer) if granted
    session = create_slot(@sandman_training, begins: august(21, year:),
                          ends: august(21, 18, year:))
    trainer_slot = create_slot(@sandman_trainer, begins: august(21, year:),
                               ends: august(21, 18, year:))
    TrainerStatus.create!(person:, slot: session, trainer_slot:, status:)
    trainer_slot
  end

  def sign_affidavit(person, year: YEAR)
    event = PersonEvent.first_or_new_for_person_year(person.id, year)
    event.sandman_affidavit = true
    event.save!(validate: false)
    event
  end

  # A burn perimeter shift, which is what counts as experience.
  def burn_shift(person, year:, position: @burn_perimeter)
    stamp_shift(person, august(28, year:), position:)
  end

  # A burn perimeter shift starting at an exact moment, for the tests that ask
  # where the experience window's two ends fall.
  def stamp_shift(person, on_duty, position: @burn_perimeter)
    Timesheet.create!(person:, position:, on_duty:, off_duty: on_duty + 6.hours,
                      additional_notes: "test shift")
  end

  # A sign-up on a Sandman shift for the year.
  def sign_up(person, year: YEAR, active: true)
    slot = create_slot(@sandman, begins: august(30, year:),
                       ends: august(30, 18, year:), active:)
    PersonSlot.create!(person:, slot:)
    slot
  end

  # Everything at once: a sandman needing nothing.
  def qualified_sandperson(callsign)
    person = sandperson(callsign)
    train(person)
    sign_affidavit(person)
    burn_shift(person, year: YEAR)
    person
  end

  def get_report(**params)
    get scheduling_sandman_qualified_path(year: YEAR, **params)
  end

  # One person's row, as the four yes/no cells the page prints: trained,
  # affidavit, experience, signed up. The verdict cell leading them is dropped —
  # it carries a badge rather than a yes or no.
  def row_flags(callsign)
    row = css_select("tbody tr").find { |tr| tr.text.include?(callsign) }
    return nil unless row

    css_select(row, "td").drop(1).map { |cell| cell.text.include?("Yes") }
  end

  def callsigns_listed
    css_select("tbody tr th").map { |th| th.text.strip }
  end

  # --- the gate ---

  test "admin may read the report" do
    get_report
    assert_response :success
  end

  test "event management may read the report" do
    sign_in_as(@event_manager)
    get_report
    assert_response :success
  end

  # Edit Slots reads the schedule reports beside this one but has no part in
  # chasing training or affidavits.
  test "edit slots may not read the report" do
    editor = create_person("Slotter")
    grant_role(editor, Role::EDIT_SLOTS)
    sign_in_as(editor)

    get_report
    assert_redirected_to me_root_path
    assert_equal DENY_MESSAGE, flash[:error]
  end

  test "another role may not read the report" do
    sign_in_as(@outsider)

    get_report
    assert_redirected_to me_root_path
    assert_equal DENY_MESSAGE, flash[:error]
  end

  # The export hands over the whole roster in one file, so it has to be held to
  # the same gate as the page. Asserted separately because the page passing
  # says nothing about a format that never renders it.
  test "a role outside the gate may not export the CSV" do
    sign_in_as(@outsider)

    get scheduling_sandman_qualified_path(year: YEAR, format: :csv)
    assert_redirected_to me_root_path
    assert_no_match(/Callsign/, response.body)
  end

  # --- who is listed ---

  test "lists active people holding the sandman position, by callsign" do
    sandperson("Zeta")
    sandperson("Anvil")

    get_report
    assert_response :success
    assert_equal %w[Anvil Zeta], callsigns_listed
  end

  test "leaves out a person who does not hold the position" do
    create_person("Bystander")
    sandperson("Sandy")

    get_report
    assert_equal ["Sandy"], callsigns_listed
  end

  # Someone who has gone inactive is not standing a burn this year, so counting
  # them would pad every figure with people no one is going to chase.
  test "leaves out a sandman who is no longer active" do
    sandperson("Stepped", status: Person::RETIRED)
    sandperson("Lapsed", status: Person::INACTIVE)
    sandperson("Sandy")

    get_report
    assert_equal ["Sandy"], callsigns_listed
  end

  test "says so when no one holds the position" do
    get_report
    assert_response :success
    assert_select "tbody tr", 0
    assert_match(/No active person holds the Sandman position/, response.body)
  end

  # --- the four answers ---

  test "a sandman with nothing answers no to everything" do
    sandperson("Empty")

    get_report
    assert_equal [false, false, false, false], row_flags("Empty")
  end

  test "passing this year's training counts as trained" do
    person = sandperson("Trainee")
    train(person)

    get_report
    assert_equal [true, false, false, false], row_flags("Trainee")
  end

  test "failing this year's training does not count as trained" do
    person = sandperson("Flunked")
    train(person, status: TraineeStatus::STATUS_NOT_PASSED)

    get_report
    assert_equal [false, false, false, false], row_flags("Flunked")
  end

  # A switched-off session teaches no one.
  test "passing a switched-off session does not count as trained" do
    person = sandperson("Cancelled")
    train(person, active: false)

    get_report
    assert_equal [false, false, false, false], row_flags("Cancelled")
  end

  test "training passed in another year does not count" do
    person = sandperson("LastYear")
    train(person, year: YEAR - 1)

    get_report
    assert_equal [false, false, false, false], row_flags("LastYear")
  end

  # Teaching the training counts the same as sitting it.
  test "teaching this year's training counts as trained" do
    person = sandperson("Teacher")
    teach(person)

    get_report
    assert_equal [true, false, false, false], row_flags("Teacher")
  end

  test "a trainer who never turned up does not count as trained" do
    person = sandperson("NoShow")
    teach(person, status: TrainerStatus::STATUS_NO_SHOW)

    get_report
    assert_equal [false, false, false, false], row_flags("NoShow")
  end

  test "teaching without holding the trainer position does not count as trained" do
    person = sandperson("Ungranted")
    teach(person, granted: false)

    get_report
    assert_equal [false, false, false, false], row_flags("Ungranted")
  end

  test "signing the affidavit for the year answers yes" do
    person = sandperson("Signer")
    sign_affidavit(person)

    get_report
    assert_equal [false, true, false, false], row_flags("Signer")
  end

  test "an affidavit signed in another year does not count" do
    person = sandperson("OldSigner")
    sign_affidavit(person, year: YEAR - 1)

    get_report
    assert_equal [false, false, false, false], row_flags("OldSigner")
  end

  test "a burn perimeter shift inside the window counts as experience" do
    person = sandperson("Veteran")
    burn_shift(person, year: CUTOFF_YEAR)

    get_report
    assert_equal [false, false, true, false], row_flags("Veteran")
  end

  test "a burn perimeter shift before the window does not count" do
    person = sandperson("Ancient")
    burn_shift(person, year: CUTOFF_YEAR - 1)

    get_report
    assert_equal [false, false, false, false], row_flags("Ancient")
  end

  # Reading an earlier year must not credit shifts rangered after it.
  test "a shift rangered after the report's year does not count" do
    person = sandperson("Future")
    burn_shift(person, year: YEAR + 1)

    get_report
    assert_equal [false, false, false, false], row_flags("Future")
  end

  # The two ends of the window, to the minute. Both are stored as the machine's
  # own wall clock, so a boundary built in another zone lands an hour out and
  # swallows the last hour of the year before -- which a shift in the middle of
  # August could never show.
  test "the first minute of the earliest year that counts is experience" do
    person = sandperson("FirstMinute")
    stamp_shift(person, Time.local(CUTOFF_YEAR, 1, 1, 0, 0, 0))

    get_report
    assert_equal [false, false, true, false], row_flags("FirstMinute")
  end

  test "the last minute before the window does not count" do
    person = sandperson("LastMinuteOut")
    stamp_shift(person, Time.local(CUTOFF_YEAR - 1, 12, 31, 23, 59, 0))

    get_report
    assert_equal [false, false, false, false], row_flags("LastMinuteOut")
  end

  test "the last minute of the report's year is experience" do
    person = sandperson("LastMinuteIn")
    stamp_shift(person, Time.local(YEAR, 12, 31, 23, 59, 0))

    get_report
    assert_equal [false, false, true, false], row_flags("LastMinuteIn")
  end

  test "the first minute after the report's year does not count" do
    person = sandperson("JustAfter")
    stamp_shift(person, Time.local(YEAR + 1, 1, 1, 0, 0, 0))

    get_report
    assert_equal [false, false, false, false], row_flags("JustAfter")
  end

  test "a shift on an unrelated position does not count as experience" do
    person = sandperson("Dirt")
    other = Position.create!(id: Position::DIRT, title: "Dirt", active: true)
    burn_shift(person, year: YEAR, position: other)

    get_report
    assert_equal [false, false, false, false], row_flags("Dirt")
  end

  test "a sandman shift sign-up answers yes" do
    person = sandperson("Booked")
    sign_up(person)

    get_report
    assert_equal [false, false, false, true], row_flags("Booked")
  end

  # The person still holds the shift, and it is still on their schedule.
  test "a sign-up on a switched-off shift still counts" do
    person = sandperson("StillBooked")
    sign_up(person, active: false)

    get_report
    assert_equal [false, false, false, true], row_flags("StillBooked")
  end

  test "a sign-up for another year does not count" do
    person = sandperson("NextYear")
    sign_up(person, year: YEAR - 1)

    get_report
    assert_equal [false, false, false, false], row_flags("NextYear")
  end

  # --- the verdict ---

  test "someone with all three requirements is qualified" do
    qualified_sandperson("Ready")

    get_report
    assert_match(/Qualified/, response.body)
    assert_equal [true, true, true, false], row_flags("Ready")
  end

  # Being signed up is reported but is not one of the three.
  test "a sign-up alone does not make someone qualified" do
    person = sandperson("JustBooked")
    sign_up(person)

    get_report
    assert_select ".badge", text: /Missing 3/
  end

  test "one missing requirement is named" do
    person = sandperson("AlmostReady")
    sign_affidavit(person)
    burn_shift(person, year: YEAR)

    get_report
    assert_select ".badge", text: /Missing training/
  end

  # --- the checks the Clubhouse asks for ---

  # The affidavit setting ships switched off, and a rule that blocks no one must
  # not mark anybody unqualified here.
  test "the affidavit is not asked for when the setting is off" do
    set_setting(Setting::SANDMAN_REQUIRE_AFFIDAVIT, "false")
    person = sandperson("NoPaperwork")
    train(person)
    burn_shift(person, year: YEAR)

    get_report
    assert_select "th", text: "Affidavit", count: 0
    assert_select ".badge", text: /Qualified/
    assert_select "a[href*='show=missing-affidavit']", 0
  end

  test "the affidavit still counts while the setting is on" do
    person = sandperson("NoPaperwork")
    train(person)
    burn_shift(person, year: YEAR)

    get_report
    assert_select "th", text: "Affidavit"
    assert_select ".badge", text: /Missing affidavit/
  end

  # A blank window reads as nought years, which asks for a burn perimeter shift
  # in the report's own year. That is what the sign-in check makes of it too,
  # and the two have to agree about who may stand a shift.
  test "a blank experience setting asks for a shift in the year itself" do
    set_setting(Setting::SANDMAN_REQUIRE_PERIMETER_EXP_WITHIN_YEARS, "")
    recent = sandperson("Recent")
    burn_shift(recent, year: YEAR)
    older = sandperson("Older")
    burn_shift(older, year: YEAR - 1)

    get_report
    assert_select "th", text: "Experience (#{YEAR} or Later)"
    assert_equal [false, false, true, false], row_flags("Recent")
    assert_equal [false, false, false, false], row_flags("Older")
  end

  # An admin narrowing the window has to narrow the report with it.
  test "the experience window follows the setting" do
    set_setting(Setting::SANDMAN_REQUIRE_PERIMETER_EXP_WITHIN_YEARS, "2")
    person = sandperson("Rusty")
    burn_shift(person, year: YEAR - 3)

    get_report
    assert_select "th", text: "Experience (#{YEAR - 2} or Later)"
    assert_equal [false, false, false, false], row_flags("Rusty")
  end

  test "a filter for a check no one is asking for shows everyone" do
    set_setting(Setting::SANDMAN_REQUIRE_AFFIDAVIT, "false")
    sandperson("Sandy")

    get_report(show: Scheduling::SandmanQualifiedController::SHOW_MISSING_AFFIDAVIT)
    assert_equal ["Sandy"], callsigns_listed
    assert_select "a[aria-label^='Remove filter']", 0
  end

  test "the export drops a column no one is asking for" do
    set_setting(Setting::SANDMAN_REQUIRE_AFFIDAVIT, "false")
    sandperson("Sandy")

    get scheduling_sandman_qualified_path(year: YEAR, format: :csv)
    assert_equal "Callsign,#{YEAR} Trained,Experience (#{CUTOFF_YEAR} or later)," \
                 "#{YEAR} Signed Up,Qualified", response.body.split("\n").first
  end

  # --- narrowing the list ---

  test "shows everyone by default" do
    qualified_sandperson("Ready")
    sandperson("NotReady")

    get_report
    assert_equal %w[NotReady Ready], callsigns_listed
  end

  test "narrows to the qualified" do
    qualified_sandperson("Ready")
    sandperson("NotReady")

    get_report(show: Scheduling::SandmanQualifiedController::SHOW_QUALIFIED)
    assert_equal ["Ready"], callsigns_listed
  end

  test "narrows to those missing training" do
    qualified_sandperson("Ready")
    sandperson("Untrained")

    get_report(show: Scheduling::SandmanQualifiedController::SHOW_MISSING_TRAINING)
    assert_equal ["Untrained"], callsigns_listed
  end

  # The list the report exists to produce: people holding a shift they cannot
  # yet stand.
  test "narrows to sign-ups who are not qualified" do
    ready = qualified_sandperson("Ready")
    sign_up(ready)
    unready = sandperson("Unready")
    sign_up(unready)
    sandperson("NotBooked")

    get_report(show: Scheduling::SandmanQualifiedController::SHOW_SIGNED_UP_UNQUALIFIED)
    assert_equal ["Unready"], callsigns_listed
  end

  test "an unknown filter shows everyone rather than narrowing to nothing" do
    sandperson("Sandy")

    get_report(show: "nonsense")
    assert_equal ["Sandy"], callsigns_listed
    assert_select "a[aria-label^='Remove filter']", 0
  end

  test "says so when a filter matches no one" do
    sandperson("Untrained")

    get_report(show: Scheduling::SandmanQualifiedController::SHOW_QUALIFIED)
    assert_select "tbody tr", 0
    assert_match(/No sandman matches this filter/, response.body)
  end

  # --- the scoreboard ---

  test "the scoreboard opens the people missing a requirement" do
    sandperson("Untrained")

    get_report
    assert_select "a[href*='show=missing-training']"
  end

  # A box with no one left to chase has nothing to open.
  test "the scoreboard does not link a requirement everyone has met" do
    qualified_sandperson("Ready")

    get_report
    assert_select "a[href*='show=missing-training']", 0
  end

  # --- the export ---

  test "exports every sandman as CSV" do
    qualified_sandperson("Ready")
    sandperson("NotReady")

    get scheduling_sandman_qualified_path(year: YEAR, format: :csv)
    assert_response :success
    assert_equal "text/csv", response.media_type

    lines = response.body.split("\n")
    assert_equal "Callsign,#{YEAR} Trained,Affidavit,Experience (#{CUTOFF_YEAR} or later)," \
                 "#{YEAR} Signed Up,Qualified", lines.first
    assert_equal "NotReady,N,N,N,N,N", lines[1]
    assert_equal "Ready,Y,Y,Y,N,Y", lines[2]
  end

  # An export named for the year that quietly held back most of it is one
  # no one can trust.
  test "the export ignores the filter on screen" do
    qualified_sandperson("Ready")
    sandperson("NotReady")

    get scheduling_sandman_qualified_path(
      year: YEAR, format: :csv,
      show: Scheduling::SandmanQualifiedController::SHOW_QUALIFIED
    )
    assert_equal 3, response.body.split("\n").size
  end

  # --- the page itself ---

  test "the year selector keeps the filter on" do
    sandperson("Untrained")

    get_report(show: Scheduling::SandmanQualifiedController::SHOW_MISSING_TRAINING)
    assert_select "a[aria-label^='Remove filter']"
    assert_select "input[name='show'][type='hidden']"
  end

  test "renders no duplicate dom ids" do
    qualified_sandperson("Ready")
    sandperson("NotReady")

    get_report
    assert_unique_dom_ids
  end
end
