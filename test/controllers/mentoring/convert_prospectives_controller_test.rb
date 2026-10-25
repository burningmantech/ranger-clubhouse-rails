# frozen_string_literal: true

require "test_helper"

# Mentoring > Convert Prospectives: who lands on the roster, the Personnel-flag
# select-all rule, and the conversion itself -- the status flip, the audit trail
# it writes, the re-verification of a stale selection, and the 422 render that
# keeps the just-converted people on screen.
class Mentoring::ConvertProspectivesControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include TrainingSlotTestHelper
  include PersonTestFactory
  include ReportCardTestHelper # card_answer
  include ActiveSupport::Testing::TimeHelpers

  YEAR = 2026
  DENY_MESSAGE = "Admin or Mentor role required to convert Prospectives."

  setup do
    travel_to Time.zone.local(YEAR, 4, 16, 12, 0, 0)
    Rails.cache.clear
    Current.reset

    @training = Position.create!(id: Position::TRAINING, title: "Training",
                                 type: Position::TYPE_TRAINING, active: true)
    # Converting grants this, via PersonStatusManagement -- without the row,
    # PersonPosition's belongs_to blows the conversion up.
    Position.create!(id: Position::ALPHA, title: "Alpha", type: Position::TYPE_FRONTLINE, active: true)
    @session = create_slot(@training, begins: Time.zone.local(YEAR, 3, 1, 9, 0, 0), description: "Bright Eyes")
    @last_year = create_slot(@training, begins: Time.zone.local(YEAR - 1, 3, 1, 9, 0, 0), description: "Old Session")

    # Carries a YEAR personnel_rank of 4 in the fixtures -- the flag that makes
    # "select all" skip a row.
    @flagged = person(:prospective_ranger)
    pass(@flagged, @session)

    @ready = create_prospective("Sparkplug")
    pass(@ready, @session)

    @also_ready = create_prospective("Quill")
    pass(@also_ready, @session)

    @untrained = create_prospective("Turnstile")

    @failed = create_prospective("Dustpan")
    pass(@failed, @session, status: TraineeStatus::STATUS_NOT_PASSED)

    @stale = create_prospective("Moonwrench")
    pass(@stale, @last_year)

    # Already an Alpha: converted last week, and must not be offered again.
    @alpha = person(:alpha_ranger)
    pass(@alpha, @session)

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

  # --- authorization -------------------------------------------------------

  test "a mentor can view the page" do
    sign_in_as(@mentor)

    get mentoring_convert_prospectives_path

    assert_response :success
    assert_match "Convert Prospectives", response.body
  end

  test "an admin can view the page" do
    sign_in_as(@admin)

    get mentoring_convert_prospectives_path

    assert_response :success
  end

  test "a role outside the gate is turned away" do
    sign_in_as(@outsider)

    get mentoring_convert_prospectives_path

    assert_redirected_to me_root_path
    assert_equal DENY_MESSAGE, flash[:error]
  end

  test "the convert action is behind the same gate" do
    sign_in_as(@outsider)

    post mentoring_convert_prospectives_path, params: { person_ids: [@ready.id] }

    assert_redirected_to me_root_path
    assert_equal Person::PROSPECTIVE, @ready.reload.status
  end

  test "the detail frame is behind the same gate" do
    sign_in_as(@outsider)

    get mentoring_convert_prospectives_detail_path(@ready)

    assert_redirected_to me_root_path
  end

  # --- the roster ----------------------------------------------------------

  # Upstream's eligibility, exactly: a Prospective with a passing training in
  # the current year, and no one else.
  test "only prospectives who passed a training this year are listed" do
    sign_in_as(@mentor)

    get mentoring_convert_prospectives_path

    assert_response :success
    assert_match @ready.callsign, response.body
    assert_match @flagged.callsign, response.body

    assert_no_match(/#{@untrained.callsign}/, response.body)
    assert_no_match(/#{@failed.callsign}/, response.body)
    assert_no_match(/#{@stale.callsign}/, response.body)
    assert_no_match(/#{@alpha.callsign}/, response.body)
  end

  # This page is a table, so the shared rank legend is worded for its row tints.
  test "the card explains the row colors in this page's own words" do
    sign_in_as(@mentor)

    get mentoring_convert_prospectives_path

    answer = card_answer("What do the row colors and the rank chips mean?")
    assert_match(/A red row is a raised Personnel flag/, answer)
    assert_match(%r{Rank 4/FLAG}, answer)
  end

  # Upstream checks `passed` alone -- a trainer who marks someone passed before
  # the session formally ends has made them eligible.
  test "a passing mark on a session still running counts" do
    sign_in_as(@mentor)
    future = create_slot(@training, begins: Time.zone.local(YEAR, 8, 1, 9, 0, 0), description: "Late Session")
    early = create_prospective("Pigment")
    pass(early, future)

    get mentoring_convert_prospectives_path

    assert_response :success
    assert_match early.callsign, response.body
  end

  test "the page ignores a year parameter" do
    sign_in_as(@mentor)

    get mentoring_convert_prospectives_path(year: 2019)

    assert_response :success
    assert_match @ready.callsign, response.body
  end

  test "an empty roster says so instead of rendering a bare form" do
    sign_in_as(@mentor)
    TraineeStatus.where(slot_id: @session.id).delete_all

    get mentoring_convert_prospectives_path

    assert_response :success
    assert_match "there is no one to convert", response.body
    assert_select "input[name='person_ids[]']", false
  end

  # --- selection -----------------------------------------------------------

  # Upstream's rule: "select all" leaves a Personnel-flagged person alone, but
  # the row keeps a checkbox so a mentor can still pick them by hand.
  test "a personnel-flagged person is skipped by select all but stays checkable" do
    sign_in_as(@mentor)

    get mentoring_convert_prospectives_path

    assert_response :success
    assert_select "#convert-person-#{@flagged.id}[data-skip-select-all]"
    assert_select "#convert-person-#{@ready.id}[data-skip-select-all]", false
    assert_match "A Personnel flag is raised on", response.body
  end

  # The Concerns cell is built by capturing the chips and falling back when the
  # capture comes out empty, so the fallback cannot drift from what is above it.
  test "the concerns cell names what was raised, or says nothing was" do
    sign_in_as(@mentor)

    get mentoring_convert_prospectives_path

    assert_response :success
    # @flagged carries a personnel flag; Intake hides that chip for the card
    # rows, so the table has to name it itself.
    assert_match "Personnel flag", response.body
    # @ready has a clean record, and an empty cell would read as missing data.
    assert_match "Nothing raised", response.body
  end

  # This table is the one page left rendering _detail_frame. Its target is
  # what lets the note links in the loaded history navigate the whole page:
  # without it the person-layout note form has no matching frame and the
  # writer gets turbo:frame-missing.
  test "row history is deferred to a lazily-loaded frame on this page" do
    sign_in_as(@mentor)

    get mentoring_convert_prospectives_path

    assert_select "turbo-frame#uf-frame-#{@ready.id}[target=_top][loading=lazy][src=?]",
                  mentoring_convert_prospectives_detail_path(@ready)
  end

  # A plain Mentor cannot open /person/:id/unified-flagging, so the history has
  # to render here rather than linking there.
  test "the detail frame renders one person's history without the page chrome" do
    sign_in_as(@mentor)

    get mentoring_convert_prospectives_detail_path(@ready)

    assert_response :success
    assert_match "uf-frame-#{@ready.id}", response.body
    assert_no_match "<html", response.body
  end

  test "a note filed from here returns to this page" do
    sign_in_as(@mentor)

    post person_intake_notes_path(@ready, origin: "mentoring_convert"),
         params: { intake_note_form: { type: "mentor", year: YEAR, note: "Ready for a pod.", ranking: "" } }

    assert_redirected_to mentoring_convert_prospectives_path(anchor: "person-#{@ready.id}")
  end

  # --- converting ----------------------------------------------------------

  test "converting flips the status and grants the alpha position" do
    sign_in_as(@mentor)

    post mentoring_convert_prospectives_path, params: { person_ids: [@ready.id, @also_ready.id] }

    assert_response :unprocessable_entity
    assert_equal Person::ALPHA, @ready.reload.status
    assert_equal Person::ALPHA, @also_ready.reload.status
    assert PersonPosition.exists?(person_id: @ready.id, position_id: Position::ALPHA)
  end

  test "converting writes the upstream audit reason to the status history" do
    sign_in_as(@mentor)

    post mentoring_convert_prospectives_path, params: { person_ids: [@ready.id] }

    row = PersonStatus.where(person_id: @ready.id).order(:created_at).last
    assert_equal Person::PROSPECTIVE, row.old_status
    assert_equal Person::ALPHA, row.new_status
    assert_equal ProspectiveConversion::AUDIT_REASON, row.reason
    assert_equal @mentor.id, row.person_source_id
  end

  # The results cannot be re-derived by a GET -- the converted people are
  # Alphas now, and so off the roster the page is drawn from.
  test "the converted people stay on the page with the results" do
    sign_in_as(@mentor)

    post mentoring_convert_prospectives_path, params: { person_ids: [@ready.id] }

    assert_response :unprocessable_entity
    assert_select "[data-controller=scroll-to-top]"
    assert_match "Converted 1 Prospective to Alpha status", response.body
    assert_match @ready.callsign, response.body
    # Converted, so no longer offered for conversion...
    assert_select "#convert-person-#{@ready.id}", false
    # ...while everyone left keeps their checkbox.
    assert_select "#convert-person-#{@also_ready.id}"
  end

  # The submitted list is stale by definition: another mentor may have acted
  # since the page was drawn, so every id is re-checked before it is trusted.
  test "an id that no longer qualifies is skipped and reported" do
    sign_in_as(@mentor)

    post mentoring_convert_prospectives_path,
         params: { person_ids: [@ready.id, @untrained.id, @alpha.id] }

    assert_response :unprocessable_entity
    assert_equal Person::ALPHA, @ready.reload.status
    assert_equal Person::PROSPECTIVE, @untrained.reload.status
    assert_match "could not be converted", response.body
  end

  test "converting no one says so rather than running an empty conversion" do
    sign_in_as(@mentor)

    post mentoring_convert_prospectives_path, params: { person_ids: [] }

    assert_redirected_to mentoring_convert_prospectives_path
    assert_equal "Select at least one Prospective to convert.", flash[:alert]
  end

  # to_i read "abc" as person 0, reported as someone who could not be
  # converted, and "#{id}x" as that person, who was converted.
  test "ids that are not ids are neither converted nor reported as skipped" do
    sign_in_as(@mentor)

    post mentoring_convert_prospectives_path,
         params: { person_ids: [@ready.id, "abc", "#{@also_ready.id}x"] }

    assert_response :unprocessable_entity
    assert_equal Person::ALPHA, @ready.reload.status
    assert_equal Person::PROSPECTIVE, @also_ready.reload.status
    assert_no_match "could not be converted", response.body
  end

  # Hand-selecting a flagged person is allowed -- "select all" skipping them is
  # a nudge, not a server-side block (upstream behaves the same way).
  test "a hand-selected personnel-flagged person still converts" do
    sign_in_as(@mentor)

    post mentoring_convert_prospectives_path, params: { person_ids: [@flagged.id] }

    assert_response :unprocessable_entity
    assert_equal Person::ALPHA, @flagged.reload.status
  end

  private

  def create_prospective(callsign)
    create_person(callsign, status: Person::PROSPECTIVE)
  end

  def pass(person, slot, status: TraineeStatus::STATUS_PASSED)
    PersonSlot.create!(person_id: person.id, slot_id: slot.id)
    TraineeStatus.create!(person_id: person.id, slot_id: slot.id, status:)
  end
end
