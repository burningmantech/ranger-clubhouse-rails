# frozen_string_literal: true

require "test_helper"

# People Search: who reaches the page, the bare-visit and empty-search guard
# states, and each criterion's filter -- status (printed as stored, never
# titleized), status-year, years rangered, photo, online course, in-person
# training (including trainer-beats-trainee and the grace-period pending
# case), ticketing, and account-created year -- plus the CSV export.
class People::SearchControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include PersonTestFactory
  include PersonPhotoTestHelper # create_photo
  include DomIdTestHelper
  include ReportCardTestHelper # assert_report_card / card_answer / assert_no_card_question
  include ActiveSupport::Testing::TimeHelpers

  YEAR = 2026
  NOW = Time.zone.local(YEAR, 8, 28, 12, 0, 0)

  setup do
    travel_to NOW
    Rails.cache.clear
    Current.reset

    # Every fixture person is parked in a status none of this page's status
    # filters ever search for, so only the people a test creates itself can
    # match a status- or status-year-scoped search.
    Person.update_all(status: Person::AUDITOR, years_as_ranger: nil)

    @training_position = Position.create!(id: Position::TRAINING, title: "Training",
                                          type: Position::TYPE_TRAINING, active: true)
    @trainer_position = Position.create!(id: Position::TRAINER, title: "Trainer",
                                         type: Position::TYPE_TRAINING, active: true)

    @admin = person(:active_ranger)
    @outsider = person(:inactive_ranger)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::VC, "Volunteer Coordinator")
    grant_role(@admin, Role::ADMIN)

    sign_in_as(@admin)
  end

  teardown do
    travel_back
    Current.reset
    Rails.cache.clear
  end

  # ---------------------------------------------------------------- access

  test "an admin reaches the index" do
    get people_search_path

    assert_response :success
    assert_select "h1", /People Search/
    assert_unique_dom_ids
  end

  test "a volunteer coordinator reaches the index" do
    vc = create_person("Coordinator")
    grant_role(vc, Role::VC)
    sign_in_as(vc)

    get people_search_path

    assert_response :success
  end

  test "someone without the admin or VC role is turned away" do
    sign_in_as(@outsider)

    get people_search_path

    assert_redirected_to me_root_path
    assert_equal "Admin or Volunteer Coordinator role required to search all accounts.",
                flash[:error] || flash[:alert]
  end

  # ---------------------------------------------------------------- bare visit

  test "a bare visit shows the open criteria panel and no results" do
    get people_search_path

    assert_response :success
    assert_select "#people-search-filters-panel", count: 1
    assert_select "#people-search-filters-panel.hidden", count: 0
    assert_select "table", count: 0
    assert_no_match(/Search Anyway/, response.body)
    assert_unique_dom_ids
  end

  test "a search with results collapses the criteria panel" do
    create_person("Someone", status: Person::ACTIVE)

    get people_search_path, params: { filter: { statuses: [Person::ACTIVE] } }

    assert_response :success
    assert_select "#people-search-filters-panel.hidden", count: 1
  end

  # ---------------------------------------------------------------- status filter

  test "a status filter matches only that status, printed as stored" do
    wanted = create_person("Sideline", status: Person::INACTIVE_EXTENSION)
    excluded = create_person("Offshift", status: Person::ACTIVE)

    get people_search_path, params: { filter: { statuses: [Person::INACTIVE_EXTENSION] } }

    assert_response :success
    assert_select "a", text: wanted.callsign
    assert_select "a", text: excluded.callsign, count: 0
    assert_select "td", text: Person::INACTIVE_EXTENSION
    assert_select "td", text: "Inactive Extension", count: 0
  end

  # ---------------------------------------------------------------- status_year

  test "status_year with statuses shows the old, new, and changed-on columns" do
    changed = create_person("Pivot", status: Person::INACTIVE)
    PersonStatus.create!(person: changed, old_status: Person::ACTIVE, new_status: Person::INACTIVE,
                         created_at: Time.zone.local(YEAR, 3, 15, 9, 0, 0))

    get people_search_path,
        params: { filter: { statuses: [Person::INACTIVE], status_year: YEAR } }

    assert_response :success
    assert_select "th", text: "Current Status"
    assert_select "th", text: "Old Status"
    assert_select "th", text: "Updated Status"
    assert_select "th", text: "Status Updated On"
    assert_select "a", text: changed.callsign
    assert_select "tbody td:nth-child(2)", text: Person::INACTIVE
    assert_select "td", text: Person::ACTIVE
    assert_match(/2026-03-15/, response.body)
  end

  test "status_year without statuses renders an error and no results" do
    get people_search_path, params: { filter: { status_year: YEAR } }

    assert_response :success
    assert_match(/Check the statuses you are interested in/, response.body)
    assert_select "table", count: 0
  end

  # ---------------------------------------------------------------- blank search guard

  test "an empty search warns instead of running" do
    # An empty filter hash vanishes entirely from a GET's query string, so the
    # marker key is carried the way a real submitted form carries it -- with
    # its default status_year, not as a bare empty hash.
    get people_search_path, params: { filter: { status_year: 0 } }

    assert_response :success
    assert_match(/No statuses are checked/, response.body)
    assert_select "table", count: 0
  end

  test "confirming an empty search runs it" do
    someone = create_person("Everybody")

    get people_search_path, params: { filter: { status_year: 0 }, confirmed: 1 }

    assert_response :success
    assert_no_match(/No statuses are checked/, response.body)
    assert_select "a", text: someone.callsign
  end

  # ---------------------------------------------------------------- years rangered

  test "years rangered filters by exact, at least, and at most" do
    one_year = create_person("Rookie", status: Person::ACTIVE, years: [2024])
    two_years = create_person("Steady", status: Person::ACTIVE, years: [2023, 2024])
    three_years = create_person("Veteran", status: Person::ACTIVE, years: [2021, 2022, 2023])

    get people_search_path,
        params: { filter: { statuses: [Person::ACTIVE], years_worked: 2, years_worked_op: "eq" } }
    assert_select "a", text: two_years.callsign
    assert_select "a", text: one_year.callsign, count: 0
    assert_select "a", text: three_years.callsign, count: 0

    get people_search_path,
        params: { filter: { statuses: [Person::ACTIVE], years_worked: 2, years_worked_op: "gte" } }
    assert_select "a", text: two_years.callsign
    assert_select "a", text: three_years.callsign
    assert_select "a", text: one_year.callsign, count: 0

    get people_search_path,
        params: { filter: { statuses: [Person::ACTIVE], years_worked: 2, years_worked_op: "lte" } }
    assert_select "a", text: two_years.callsign
    assert_select "a", text: one_year.callsign
    assert_select "a", text: three_years.callsign, count: 0
  end

  # ---------------------------------------------------------------- photo status

  test "photo status filters missing versus approved" do
    has_photo = create_person("Framed", status: Person::ACTIVE)
    photo = create_photo(person: has_photo, status: PersonPhoto::APPROVED)
    has_photo.update_columns(person_photo_id: photo.id)
    no_photo = create_person("Blank", status: Person::ACTIVE)

    get people_search_path,
        params: { filter: { statuses: [Person::ACTIVE], photo_status: PersonPhoto::APPROVED } }
    assert_select "a", text: has_photo.callsign
    assert_select "a", text: no_photo.callsign, count: 0

    get people_search_path,
        params: { filter: { statuses: [Person::ACTIVE], photo_status: PersonPhoto::MISSING } }
    assert_select "a", text: no_photo.callsign
    assert_select "a", text: has_photo.callsign, count: 0
  end

  test "photo status filters rejected photos" do
    rejected = create_person("Flagged", status: Person::ACTIVE)
    rejected_photo = create_photo(person: rejected, status: PersonPhoto::REJECTED)
    rejected.update_columns(person_photo_id: rejected_photo.id)
    approved = create_person("Cleared", status: Person::ACTIVE)
    approved_photo = create_photo(person: approved, status: PersonPhoto::APPROVED)
    approved.update_columns(person_photo_id: approved_photo.id)

    get people_search_path,
        params: { filter: { statuses: [Person::ACTIVE], photo_status: PersonPhoto::REJECTED } }

    assert_select "a", text: rejected.callsign
    assert_select "a", text: approved.callsign, count: 0
  end

  # ---------------------------------------------------------------- online course

  test "online course status filters missing, started, and completed" do
    missing = create_person("Unenrolled", status: Person::ACTIVE)
    started = create_person("Enrolled", status: Person::ACTIVE)
    PersonOnlineCourse.create!(person: started, position_id: Position::TRAINING, year: YEAR,
                               enrolled_at: NOW - 1.day)
    completed = create_person("Graduated", status: Person::ACTIVE)
    PersonOnlineCourse.create!(person: completed, position_id: Position::TRAINING, year: YEAR,
                               enrolled_at: NOW - 2.days, completed_at: NOW - 1.day)

    get people_search_path,
        params: { filter: { statuses: [Person::ACTIVE], online_course_status: "missing" } }
    assert_select "a", text: missing.callsign
    assert_select "a", text: started.callsign, count: 0
    assert_select "a", text: completed.callsign, count: 0

    get people_search_path,
        params: { filter: { statuses: [Person::ACTIVE], online_course_status: "started" } }
    assert_select "a", text: started.callsign
    assert_select "a", text: missing.callsign, count: 0

    get people_search_path,
        params: { filter: { statuses: [Person::ACTIVE], online_course_status: "completed" } }
    assert_select "a", text: completed.callsign
    assert_select "a", text: started.callsign, count: 0
  end

  # ---------------------------------------------------------------- ticketing

  test "ticketing status filters started and not-finished" do
    not_started = create_person("NoTix", status: Person::ACTIVE)
    started_only = create_person("Working", status: Person::ACTIVE)
    PersonEvent.create!(person: started_only, year: YEAR, ticketing_started_at: NOW - 1.day)
    finished = create_person("Done", status: Person::ACTIVE)
    PersonEvent.create!(person: finished, year: YEAR, ticketing_started_at: NOW - 2.days,
                        ticketing_finished_at: NOW - 1.day)

    get people_search_path,
        params: { filter: { statuses: [Person::ACTIVE], ticketing_status: "started" } }
    assert_select "a", text: started_only.callsign
    assert_select "a", text: finished.callsign
    assert_select "a", text: not_started.callsign, count: 0

    get people_search_path,
        params: { filter: { statuses: [Person::ACTIVE], ticketing_status: "not-finished" } }
    assert_select "a", text: started_only.callsign
    assert_select "a", text: finished.callsign, count: 0
    assert_select "a", text: not_started.callsign, count: 0
  end

  test "ticketing status filters not-started and finished" do
    not_started = create_person("NoTix2", status: Person::ACTIVE)
    started_only = create_person("Working2", status: Person::ACTIVE)
    PersonEvent.create!(person: started_only, year: YEAR, ticketing_started_at: NOW - 1.day)
    finished = create_person("Done2", status: Person::ACTIVE)
    PersonEvent.create!(person: finished, year: YEAR, ticketing_started_at: NOW - 2.days,
                        ticketing_finished_at: NOW - 1.day)

    get people_search_path,
        params: { filter: { statuses: [Person::ACTIVE], ticketing_status: "not-started" } }
    assert_select "a", text: not_started.callsign
    assert_select "a", text: started_only.callsign, count: 0
    assert_select "a", text: finished.callsign, count: 0

    get people_search_path,
        params: { filter: { statuses: [Person::ACTIVE], ticketing_status: "finished" } }
    assert_select "a", text: finished.callsign
    assert_select "a", text: started_only.callsign, count: 0
    assert_select "a", text: not_started.callsign, count: 0
  end

  test "ticketing not-finished-claimed additionally requires a claimed ticket" do
    unclaimed = create_person("Waiting", status: Person::ACTIVE)
    PersonEvent.create!(person: unclaimed, year: YEAR, ticketing_started_at: NOW - 1.day)
    claimed = create_person("Grabbed", status: Person::ACTIVE)
    PersonEvent.create!(person: claimed, year: YEAR, ticketing_started_at: NOW - 1.day)
    AccessDocument.create!(person: claimed, type: AccessDocument::STAFF_CREDENTIAL,
                           status: AccessDocument::CLAIMED)

    get people_search_path,
        params: { filter: { statuses: [Person::ACTIVE], ticketing_status: "not-finished-claimed" } }

    assert_select "a", text: claimed.callsign
    assert_select "a", text: unclaimed.callsign, count: 0
  end

  # ---------------------------------------------------------------- training

  test "training status covers passed, failed, missing, and signed-up" do
    passed = create_person("Graduate", status: Person::ACTIVE)
    passed_slot = Slot.create!(position: @training_position,
                               begins: Time.zone.local(YEAR, 5, 1, 9, 0, 0),
                               ends: Time.zone.local(YEAR, 5, 1, 13, 0, 0), max: 10)
    PersonSlot.create!(person: passed, slot: passed_slot)
    TraineeStatus.create!(person: passed, slot: passed_slot, status: TraineeStatus::STATUS_PASSED)

    # Outside the grace period with no passed record -- a definite failure.
    failed = create_person("NoShow", status: Person::ACTIVE)
    failed_slot = Slot.create!(position: @training_position,
                               begins: Time.zone.local(YEAR, 5, 10, 9, 0, 0),
                               ends: Time.zone.local(YEAR, 5, 10, 13, 0, 0), max: 10)
    PersonSlot.create!(person: failed, slot: failed_slot)
    TraineeStatus.create!(person: failed, slot: failed_slot, status: TraineeStatus::STATUS_NOT_PASSED)

    missing = create_person("NeverSignedUp", status: Person::ACTIVE)

    get people_search_path,
        params: { filter: { statuses: [Person::ACTIVE], training_status: "passed" } }
    assert_select "a", text: passed.callsign
    assert_select "a", text: failed.callsign, count: 0

    get people_search_path,
        params: { filter: { statuses: [Person::ACTIVE], training_status: "failed" } }
    assert_select "a", text: failed.callsign
    assert_select "a", text: passed.callsign, count: 0

    get people_search_path,
        params: { filter: { statuses: [Person::ACTIVE], training_status: "missing" } }
    assert_select "a", text: missing.callsign
    assert_select "a", text: passed.callsign, count: 0

    get people_search_path,
        params: { filter: { statuses: [Person::ACTIVE], training_status: "signed-up" } }
    assert_select "a", text: passed.callsign
    assert_select "a", text: failed.callsign
    assert_select "a", text: missing.callsign, count: 0
  end

  test "a pending training verdict stays pending inside the grace period" do
    pending = create_person("JustFinished", status: Person::ACTIVE)
    # Ends two days before "now" -- inside the 72-hour grace window, with no
    # trainee_status recorded yet.
    slot = Slot.create!(position: @training_position,
                        begins: Time.zone.local(YEAR, 8, 26, 8, 0, 0),
                        ends: Time.zone.local(YEAR, 8, 26, 12, 0, 0), max: 10)
    PersonSlot.create!(person: pending, slot: slot)

    get people_search_path,
        params: { filter: { statuses: [Person::ACTIVE], columns: ["training_status"] } }

    assert_response :success
    assert_select "a", text: pending.callsign
    assert_match(/pending/, response.body)
  end

  test "an entered verdict fails at once; only an unscored session waits out the grace period" do
    # Ends two days before "now" -- inside the 72-hour grace window.
    slot = Slot.create!(position: @training_position,
                        begins: Time.zone.local(YEAR, 8, 26, 8, 0, 0),
                        ends: Time.zone.local(YEAR, 8, 26, 12, 0, 0), max: 10)
    { "Awaiting" => TraineeStatus::STATUS_PENDING,
      "Absentee" => TraineeStatus::STATUS_NO_SHOW,
      "Unready" => TraineeStatus::STATUS_NOT_PASSED }.each do |callsign, status|
      person = create_person(callsign, status: Person::ACTIVE)
      PersonSlot.create!(person:, slot:)
      TraineeStatus.create!(person:, slot:, status:)
    end

    get people_search_path,
        params: { filter: { statuses: [Person::ACTIVE], training_status: "failed" } }

    assert_select "a", text: "Absentee"
    assert_select "a", text: "Unready"
    assert_select "a", text: "Awaiting", count: 0
  end

  test "a trainer verdict outranks a trainee verdict for the same person" do
    both = create_person("BothRoles", status: Person::ACTIVE)

    trainer_slot = Slot.create!(position: @trainer_position,
                                begins: Time.zone.local(YEAR, 5, 1, 9, 0, 0),
                                ends: Time.zone.local(YEAR, 5, 1, 13, 0, 0), max: 10)
    PersonSlot.create!(person: both, slot: trainer_slot)
    TrainerStatus.create!(person: both, slot: trainer_slot, trainer_slot: trainer_slot,
                          status: TrainerStatus::STATUS_ATTENDED)

    # A trainee slot that would read as failed on its own -- the trainer
    # signup has to win for this person to show up as passed.
    trainee_slot = Slot.create!(position: @training_position,
                                begins: Time.zone.local(YEAR, 5, 10, 9, 0, 0),
                                ends: Time.zone.local(YEAR, 5, 10, 13, 0, 0), max: 10)
    PersonSlot.create!(person: both, slot: trainee_slot)
    TraineeStatus.create!(person: both, slot: trainee_slot, status: TraineeStatus::STATUS_NOT_PASSED)

    get people_search_path,
        params: { filter: { statuses: [Person::ACTIVE], training_status: "passed" } }
    assert_select "a", text: both.callsign

    get people_search_path,
        params: { filter: { statuses: [Person::ACTIVE], training_status: "failed" } }
    assert_select "a", text: both.callsign, count: 0
  end

  test "a trainer no-show verdict reads as failed" do
    no_show = create_person("Absent", status: Person::ACTIVE)
    trainer_slot = Slot.create!(position: @trainer_position,
                                begins: Time.zone.local(YEAR, 5, 1, 9, 0, 0),
                                ends: Time.zone.local(YEAR, 5, 1, 13, 0, 0), max: 10)
    PersonSlot.create!(person: no_show, slot: trainer_slot)
    TrainerStatus.create!(person: no_show, slot: trainer_slot, trainer_slot: trainer_slot,
                          status: TrainerStatus::STATUS_NO_SHOW)

    get people_search_path,
        params: { filter: { statuses: [Person::ACTIVE], training_status: "failed" } }
    assert_select "a", text: no_show.callsign

    get people_search_path,
        params: { filter: { statuses: [Person::ACTIVE], training_status: "passed" } }
    assert_select "a", text: no_show.callsign, count: 0
  end

  # ---------------------------------------------------------------- year_created

  test "year_created 1 means created_at is null" do
    legacy = create_person("Ancient", status: Person::ACTIVE)
    legacy.update_columns(created_at: nil)
    recent = create_person("Newcomer", status: Person::ACTIVE)
    recent.update_columns(created_at: Time.zone.local(2015, 6, 1))

    get people_search_path,
        params: { filter: { statuses: [Person::ACTIVE],
                            year_created: PersonSearchForm::CREATED_PRIOR_SENTINEL } }

    assert_select "a", text: legacy.callsign
    assert_select "a", text: recent.callsign, count: 0
  end

  # ---------------------------------------------------------------- csv export

  test "the csv export carries name and email columns" do
    exported = create_person("Exportable", status: Person::ACTIVE)

    get people_search_path(format: :csv), params: { filter: { statuses: [Person::ACTIVE] } }

    assert_response :success
    assert_equal "text/csv", response.media_type
    assert_match(/people-search\.csv/, response.headers["Content-Disposition"])

    rows = response.body.split("\n")
    assert_equal "Callsign,First Name,Last Name,Email,Status", rows.first
    assert(rows.any? { |row| row.start_with?("#{exported.callsign},") && row.include?(exported.email) })
  end

  test "the csv export formats optional columns, including dates" do
    loaded = create_person("Loaded", status: Person::ACTIVE, years: [2023, 2024])
    loaded.update_columns(created_at: Time.zone.local(2020, 6, 15))

    get people_search_path(format: :csv),
        params: { filter: { statuses: [Person::ACTIVE], columns: %w[years_worked created_at] } }

    assert_response :success
    rows = response.body.split("\n")
    assert_equal "Callsign,First Name,Last Name,Email,Status,Years Rangered,Account Created", rows.first
    row = rows.find { |r| r.start_with?("#{loaded.callsign},") }
    assert_equal "#{loaded.callsign},Loaded,Shifter,#{loaded.email},active,2,2020-06-15", row
  end

  test "csv export withholds rows when the empty-search guard blocks the html flow" do
    create_person("Someone", status: Person::ACTIVE)

    get people_search_path(format: :csv), params: { filter: { status_year: 0 } }

    assert_response :success
    assert_equal 1, response.body.split("\n").size
  end

  test "csv export withholds rows when status_year lacks statuses" do
    create_person("Someone", status: Person::ACTIVE)

    get people_search_path(format: :csv), params: { filter: { status_year: YEAR } }

    assert_response :success
    assert_equal 1, response.body.split("\n").size
  end
  # ---------------------------------------------------------------- guards render first

  test "the empty-search warning renders above the criteria panel" do
    get people_search_path, params: { filter: { status_year: 0 } }

    assert_response :success
    warning_at = response.body.index("No statuses are checked")
    panel_at = response.body.index("people-search-filters-panel")
    assert warning_at, "expected the warning callout"
    assert panel_at, "expected the criteria panel"
    assert warning_at < panel_at, "warning must render before the panel so it lands above the fold"
  end

  test "a years rangered value that is not a whole number is named, not dropped" do
    create_person("Someone", status: Person::ACTIVE)

    get people_search_path,
        params: { filter: { statuses: [Person::ACTIVE], years_worked: "abc" } }

    assert_response :success
    assert_match(/Years rangered must be a whole number/, response.body)
    assert_select "table", count: 0
  end

  # ---------------------------------------------------------------- pagination

  test "an out-of-range page is clamped instead of rendering nothing" do
    only = create_person("Solo", status: Person::ACTIVE)

    get people_search_path,
        params: { filter: { statuses: [Person::ACTIVE] }, page: 99 }

    assert_response :success
    assert_select "a", text: only.callsign

    get people_search_path,
        params: { filter: { statuses: [Person::ACTIVE] }, page: 0 }

    assert_response :success
    assert_select "a", text: only.callsign
  end

  test "a single page of results draws no pagination controls" do
    create_person("Solo2", status: Person::ACTIVE)

    get people_search_path, params: { filter: { statuses: [Person::ACTIVE] } }

    assert_response :success
    assert_no_match(/Next Page/, response.body)
    assert_no_match(/Page 1 of/, response.body)
  end

  # ---------------------------------------------------------------- the card

  # The card's two questions. Each is spelled once: one test reads its answer
  # and the other expects it gone, and that check would keep passing against
  # wording that had merely changed.
  DATES_QUESTION = "Why do some dates show a dash?"
  EXPORT_QUESTION = "Does the CSV export stop at this page?"

  # The card's two pairs are each about one state of the results: a date column
  # on screen, and more than one page. A plain single page has no card.
  test "the card explains blank dates only when a date column is shown" do
    create_person("Dated", status: Person::ACTIVE)

    get people_search_path, params: { filter: { statuses: [Person::ACTIVE], columns: ["created_at"] } }

    assert_report_card
    assert_match(/blank for older accounts/, card_answer(DATES_QUESTION))
    assert_no_card_question EXPORT_QUESTION

    get people_search_path, params: { filter: { statuses: [Person::ACTIVE] } }

    assert_report_card count: 0
  end

  # One row a page for the length of the request, so two people are enough to
  # reach a second page.
  test "the card says the export carries every match once the results are paged" do
    2.times { |n| create_person("Paged#{n}", status: Person::ACTIVE) }

    stub_const(People::SearchController, :PAGE_SIZE, 1) do
      get people_search_path, params: { filter: { statuses: [Person::ACTIVE] } }
    end

    assert_match(/Page 1 of \d+/, response.body)
    assert_match(/includes every match/, card_answer(EXPORT_QUESTION))
    assert_no_card_question DATES_QUESTION
  end

  test "paged results keep their pager a navigation landmark" do
    2.times { |n| create_person("Landmark#{n}", status: Person::ACTIVE) }

    stub_const(People::SearchController, :PAGE_SIZE, 1) do
      get people_search_path, params: { filter: { statuses: [Person::ACTIVE] } }
    end

    assert_select "[role=navigation][aria-label='Result pages']", text: /Page 1 of 2 · 2 people/
  end

  # ---------------------------------------------------------------- status vocabulary

  test "a non-norm status renders as a badge while active stays plain text" do
    create_person("Sidelined", status: Person::INACTIVE)
    create_person("Standing", status: Person::ACTIVE)

    get people_search_path,
        params: { filter: { statuses: [Person::INACTIVE, Person::ACTIVE] } }

    assert_response :success
    assert_select "td .badge", text: /#{Person::INACTIVE}/
    assert_select "td .badge", text: Person::ACTIVE, count: 0
  end
  # ---------------------------------------------------------------- criteria categories

  test "a bare visit opens only the Status category" do
    get people_search_path

    assert_response :success
    assert_select "details#people-search-status-category[open]"
    assert_select "details#people-search-experience-category[open]", count: 0
    assert_select "details#people-search-account-category[open]", count: 0
    assert_select "details#people-search-columns-category[open]", count: 0
  end

  test "a category holding a criterion opens with the panel" do
    get people_search_path,
        params: { filter: { statuses: [Person::ACTIVE], photo_status: PersonPhoto::MISSING,
                            columns: ["created_at"] } }

    assert_response :success
    # Status and the two categories carrying a criterion open; the untouched
    # one stays collapsed.
    assert_select "details#people-search-status-category[open]"
    assert_select "details#people-search-experience-category[open]"
    assert_select "details#people-search-columns-category[open]"
    assert_select "details#people-search-account-category[open]", count: 0
  end

  test "a closed category names how many criteria it holds" do
    get people_search_path,
        params: { filter: { statuses: [Person::ACTIVE], columns: %w[created_at years_worked] } }

    assert_response :success
    # The columns category is open because it holds two, and says so.
    assert_select "details#people-search-columns-category summary", text: /2 selected/
    # The untouched one invites instead of counting.
    assert_select "details#people-search-account-category summary", text: /Show account options/
  end

  test "the criteria panel uses the shared filter-panel building blocks" do
    get people_search_path

    assert_response :success
    # ui_disclosure cards, not ad-hoc accordions or bespoke fieldsets.
    assert_select "#people-search-filters-panel details.group", count: 4
    assert_select "#people-search-filters-panel fieldset", count: 0
    # Fields ride form_row, so they share the row and wrap together.
    assert_select "#people-search-filters-panel div.flex.flex-col"
    assert_unique_dom_ids
  end

  # One flat list of every status, by decree -- no standing captions, no
  # per-group select-all.
  test "the status checkboxes are one flat list" do
    get people_search_path

    assert_response :success
    assert_select "#people-search-filters-panel [role=group]", count: 0
    Person::ALL_STATUSES.each do |status|
      assert_select "#people-search-status-#{status.parameterize}"
    end
  end
end
