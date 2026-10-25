# frozen_string_literal: true

require "test_helper"

# Everyone the intake teams touched in a year, for an Admin. The lines, the
# pane and the shared filters are covered by the /vc suite
# (test/controllers/vc/unified_flagging_controller_test.rb); what is tested
# here is what differs: the Admin-only gate, the roster rule, the two
# year-exact filters, the retitled third group, the jump list, the export, and
# that no note control renders.
class People::UnifiedFlaggingControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include ReportCardTestHelper # assert_report_card / card_answer
  include TrainingSlotTestHelper # create_slot
  include ActiveSupport::Testing::TimeHelpers

  YEAR = 2026
  DENY_MESSAGE = "Admin role required to view unified flagging."

  setup do
    travel_to Time.zone.local(YEAR, 4, 16, 12, 0, 0)
    Rails.cache.clear
    Current.reset

    # The fixtures' 2026: prospective_ranger carries a personnel_rank of 4 and
    # two Personnel notes, past_prospective_ranger one Personnel note and
    # nothing else -- and, with no person_status row, was no Prospective this
    # year. ranger_with_custom_gender carries a 2024 bonk and nothing else, so
    # they are listed for 2024 and not for 2026.
    @flagged = person(:prospective_ranger)
    @noted = person(:past_prospective_ranger)
    @bonked = person(:ranger_with_custom_gender)

    @admin = person(:auditor_ranger)
    @vc = person(:echelon_ranger)
    @intake = person(:active_ranger)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::VC, "Volunteer Coordinator")
    ensure_role(Role::INTAKE, "Intake")

    grant_role(@admin, Role::ADMIN)
    grant_role(@vc, Role::VC)
    grant_role(@intake, Role::INTAKE)

    Current.person = @admin
  end

  teardown do
    Current.reset
    travel_back
  end

  # --- authorization -------------------------------------------------------

  test "admin can view the report" do
    sign_in_as(@admin)

    get people_unified_flagging_path

    assert_response :success
    assert_match "#{YEAR} Unified Flagging", response.body
  end

  # Unlike /vc/unified-flagging, VC and Intake do not pass: the roster is not
  # the pipeline, and a Personnel note on any Ranger is on it.
  test "a volunteer coordinator is turned away" do
    sign_in_as(@vc)

    get people_unified_flagging_path

    assert_redirected_to me_root_path
    assert_equal DENY_MESSAGE, flash[:error]
  end

  test "intake is turned away" do
    sign_in_as(@intake)

    get people_unified_flagging_path

    assert_redirected_to me_root_path
  end

  # --- the roster ----------------------------------------------------------

  test "whoever was noted, ranked, flagged or bonked in the year is listed, and no one else" do
    sign_in_as(@admin)

    get people_unified_flagging_path

    assert_response :success
    assert_select "li#person-#{@flagged.id}"
    assert_select "li#person-#{@noted.id}"
    assert_select "li#person-#{@bonked.id}", count: 0
    assert_match "Showing 2 of 2 people", response.body

    get people_unified_flagging_path(year: 2024)

    assert_response :success
    assert_match "2024 Unified Flagging", response.body
    assert_select "li#person-#{@bonked.id}"
    assert_select "li#person-#{@flagged.id}"
    assert_select "li#person-#{@noted.id}", count: 0
  end

  # One list by callsign, not the pipeline pages' severity sections: the
  # sections opened the page on the flagged few with everyone else out of
  # sight below them. The tiles keep the shared groups, with the third
  # retitled: here it holds whoever carries no current mark, whatever their
  # status, not "other potential Alphas".
  test "the list is one roster by callsign, and the tiles count the groups" do
    sign_in_as(@admin)

    get people_unified_flagging_path

    assert_select "section [role=heading]", text: /Everyone Listed/
    assert_select "section [role=heading]", text: /Rank 3\/4 or bonk/, count: 0
    # PastProspective sorts before ProspectiveNewbie; the severity order put
    # the flagged person first.
    assert_operator response.body.index("id=\"person-#{@noted.id}\""), :<,
                    response.body.index("id=\"person-#{@flagged.id}\"")
    assert_select "li#person-#{@flagged.id} a.review-line-flagged"
    assert_match "A Personnel flag is raised on #{@flagged.callsign}", response.body
    assert_match "Everyone Else", response.body
    assert_no_match "Other Potential Alphas", response.body
    assert_select "a[href=?]", people_unified_flagging_path(year: YEAR, section: "personnel")

    get people_unified_flagging_path(section: "other")

    assert_response :success
    assert_select "li#person-#{@noted.id}"
    assert_select "li#person-#{@flagged.id}", count: 0
    assert_match "Section: Everyone Else", response.body
    assert_select "select[name=section] option[selected][value=other]"
  end

  test "the card says who is listed, when training applies, and what the export holds" do
    sign_in_as(@admin)

    get people_unified_flagging_path

    assert_report_card
    assert_match(/whatever their status/, card_answer("Who is listed?"))
    assert_match(/pipeline/, card_answer("When does a name carry a training word?"))
    assert_match(/One row per person/, card_answer("What does the export contain?"))
    assert_match(/most serious mark/, card_answer("What is the colored chip on an entry?"))

    get people_unified_flagging_path(year: 2012)

    assert_response :success
    assert_match "No notes, ranks, flags, or bonks were recorded in 2012", response.body
    assert_report_card count: 0
  end

  # --- the filters ---------------------------------------------------------

  test "the ranking filter keeps whoever was given that rank in the year" do
    sign_in_as(@admin)

    get people_unified_flagging_path(rank: "4")

    assert_response :success
    assert_select "li#person-#{@flagged.id}"
    assert_select "li#person-#{@noted.id}", count: 0
    assert_match "Ranking: 4/FLAG", response.body

    get people_unified_flagging_path(rank: "any")

    assert_select "li#person-#{@flagged.id}"
    assert_select "li#person-#{@noted.id}", count: 0

    # The VC rank of 3 is 2025's: on the gray line, and not this year's.
    get people_unified_flagging_path(rank: "3")

    assert_match "matched those filters", response.body
  end

  # A retake year ranks two sessions, and either rank is one the year gave.
  test "the ranking filter matches every rank a retake year gave" do
    sign_in_as(@admin)
    [[7, Intake::BELOW_AVERAGE], [21, Intake::ABOVE_AVERAGE]].each do |day, rank|
      slot = create_slot(training_position, begins: Time.zone.local(YEAR, 3, day, 9, 0, 0))
      PersonSlot.create!(person_id: @noted.id, slot_id: slot.id)
      TraineeStatus.create!(person_id: @noted.id, slot_id: slot.id, rank:)
    end

    get people_unified_flagging_path(rank: Intake::ABOVE_AVERAGE.to_s)

    assert_select "li#person-#{@noted.id}"

    get people_unified_flagging_path(rank: Intake::BELOW_AVERAGE.to_s)

    assert_select "li#person-#{@noted.id}"
  end

  test "the notes filter keeps whoever that team wrote about in the year" do
    sign_in_as(@admin)

    get people_unified_flagging_path(notes: "personnel")

    assert_response :success
    assert_select "li#person-#{@flagged.id}"
    assert_select "li#person-#{@noted.id}"
    assert_match "Notes: Personnel", response.body

    get people_unified_flagging_path(notes: "any")

    assert_match "Showing 2 of 2 people", response.body

    # The VC note is 2025's.
    get people_unified_flagging_path(notes: "vc")

    assert_match "matched those filters", response.body
  end

  # A stale bookmark or a typo reads as "all", never as "nothing" -- and so
  # does a bare Apply.
  test "an unknown filter value is ignored" do
    sign_in_as(@admin)

    get people_unified_flagging_path(rank: "9", notes: "typo", training: "typo", year: YEAR, q: "")

    assert_response :success
    assert_match "Showing 2 of 2 people", response.body
    assert_no_match "Ranking:", response.body
    assert_no_match "Notes:", response.body
    assert_no_match "Training:", response.body
  end

  # A hand-made nested value reached every chip's URL and raised there.
  test "a nested filter value reads as no filter" do
    sign_in_as(@admin)

    get people_unified_flagging_path, params: { training: { x: "y" }, rank: "4" }

    assert_response :success
    assert_select "li#person-#{@flagged.id}"
    assert_match "Showing 1 of 2 people", response.body
  end

  test "the export link carries the filters that narrow the list" do
    sign_in_as(@admin)

    get people_unified_flagging_path(rank: "4", notes: "personnel")

    assert_select "a[href=?]", people_unified_flagging_path(rank: "4", notes: "personnel", year: YEAR, format: :csv)
  end

  # --- training ------------------------------------------------------------

  # Training is a pipeline question: PastProspective is listed for a Personnel
  # note and was no Prospective this year, so their line carries no training
  # word and the Training filter's "No sign-up" does not take them.
  test "the training word and the Training filter cover only the year's pipeline" do
    sign_in_as(@admin)

    get people_unified_flagging_path

    assert_select "li#person-#{@flagged.id} a", text: /No training sign-up/
    assert_select "li#person-#{@noted.id} a"
    assert_select "li#person-#{@noted.id} a", text: /training/i, count: 0

    get people_unified_flagging_path(training: "none")

    assert_select "li#person-#{@flagged.id}"
    assert_select "li#person-#{@noted.id}", count: 0
  end

  # --- the jump list -------------------------------------------------------

  # The links are plain fragments for the browser: a Turbo visit of the same
  # URL refetched the whole roster and threw away any unapplied filter text.
  test "the jump list offers every line shown, and nothing with one line" do
    sign_in_as(@admin)

    get people_unified_flagging_path

    assert_select "a[href=?][data-turbo=false]", "#person-#{@flagged.id}", text: @flagged.callsign
    assert_select "a[href=?][data-turbo=false]", "#person-#{@noted.id}", text: @noted.callsign

    get people_unified_flagging_path(q: @flagged.callsign)

    assert_select "li#person-#{@flagged.id}"
    assert_select "a[href^='#person-']", count: 0
  end

  # --- the line --------------------------------------------------------------

  # A trainer's note is the other thing that lists a person here, and the
  # shared line names only the intake teams' notes. The session has ended, as
  # the pane shows a trainer's notes only once it has.
  test "a line names a trainer's note written in the year" do
    sign_in_as(@admin)
    slot = create_slot(training_position, begins: Time.zone.local(YEAR, 3, 14, 9, 0, 0))
    PersonSlot.create!(person_id: @noted.id, slot_id: slot.id)
    note = TraineeNote.create!(person_id: @noted.id, slot_id: slot.id, note: "Quiet on the radio.",
                               person_source_id: @admin.id)

    get people_unified_flagging_path

    assert_select "li#person-#{@noted.id} a", text: /Training #{note.reload.created_at.strftime("%b %-d, %Y")}/
    assert_select "li#person-#{@flagged.id} a", text: /Training \w+ \d/, count: 0
  end

  # --- the review pane -----------------------------------------------------

  test "selecting a name fills the pane, read-only" do
    sign_in_as(@admin)

    get people_unified_flagging_path(person: @flagged.id)

    assert_response :success
    assert_select "li#person-#{@flagged.id} a[aria-current=true][href=?]",
                  people_unified_flagging_path(year: YEAR, person: @flagged.id)
    assert_select "aside.review-pane turbo-frame#uf-pane[target=_top] [data-review-id=?]", @flagged.id.to_s
    assert_select "aside.review-pane [role=alert]", text: /Take no actions on #{@flagged.callsign}/
    assert_no_match(/Add .* Note/, response.body)
    assert_no_match new_person_intake_note_path(@flagged), response.body
    # Scoped to the pane: the navbar's own logout link is a Turbo delete too.
    assert_select "aside.review-pane [data-turbo-method=delete]", count: 0
  end

  test "a line loads only the pane" do
    sign_in_as(@admin)

    get people_unified_flagging_path(person: @flagged.id), headers: { "Turbo-Frame" => "uf-pane" }

    assert_response :success
    assert_select "turbo-frame#uf-pane [data-review-id=?]", @flagged.id.to_s
    assert_select "li[id^=person-]", count: 0
    assert_no_match "<html", response.body
  end

  # A pane request reads only the person it names, and the page's filters
  # still decide whether that person is on the page to be selected.
  test "a line's pane reads only its person, under the page's filters" do
    sign_in_as(@admin)

    get people_unified_flagging_path(person: @noted.id), headers: { "Turbo-Frame" => "uf-pane" }

    assert_select "turbo-frame#uf-pane [data-review-id=?]", @noted.id.to_s

    get people_unified_flagging_path(person: @flagged.id, rank: "1"), headers: { "Turbo-Frame" => "uf-pane" }

    assert_select "turbo-frame#uf-pane [data-review-id]", count: 0
    assert_select "turbo-frame#uf-pane", text: /Select a name/
  end

  # --- the export ----------------------------------------------------------

  test "the export is one row per person shown, in the page's order, with the year's facts" do
    sign_in_as(@admin)
    flagged_latest = PersonIntakeNote.where(person_id: @flagged.id, year: YEAR, type: "personnel", is_log: false)
                                     .maximum(:created_at)
    noted_latest = person_intake_note(:past_prospective_personnel_note_2026).created_at

    get people_unified_flagging_path(year: YEAR, format: :csv)

    assert_response :success
    assert_match "#{YEAR}-unified-flagging.csv", response.headers["Content-Disposition"]

    rows = response.body.split("\n")
    assert_equal "Callsign,Name,Status,Personnel Flag,Personnel Rank,RRN Rank,VC Rank,Training Rank," \
                 "Mentor Rank,Bonk,Training,Notes From", rows.first
    assert_equal 3, rows.size, "header plus the two people listed"
    # By callsign, as the page lists them, and with no training cell for
    # PastProspective, whom training does not concern this year.
    assert_equal [CsvExportConcern.build([[@noted.callsign, "Past Prospective", @noted.status, "N",
                                           nil, nil, nil, nil, nil, nil, nil,
                                           "Personnel #{noted_latest.strftime("%b %-d, %Y")}"]]),
                  CsvExportConcern.build([[@flagged.callsign, "Prospect Newbie", @flagged.status, "Y",
                                           4, nil, nil, nil, nil, nil, "none",
                                           "Personnel #{flagged_latest.strftime("%b %-d, %Y")}"]])],
                 rows.drop(1)

    get people_unified_flagging_path(year: YEAR, rank: "1", format: :csv)

    assert_equal 1, response.body.split("\n").size, "the export follows the filters"
  end

  # The pane's early answer took any request carrying its frame header, and
  # found no CSV pane to render.
  test "the export answers with its file even under a frame header" do
    sign_in_as(@admin)

    get people_unified_flagging_path(year: YEAR, format: :csv), headers: { "Turbo-Frame" => "uf-pane" }

    assert_response :success
    assert_equal "text/csv", response.media_type
  end

  private

  def training_position
    Position.find_or_initialize_by(id: Position::TRAINING).tap do |position|
      position.update!(title: "In-Person Training", type: Position::TYPE_TRAINING, active: true)
    end
  end
end
