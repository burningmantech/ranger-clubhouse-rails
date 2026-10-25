# frozen_string_literal: true

require "test_helper"

# Training > Current Mentees: the mentee-ART-only gate, the split between
# reading the roster and revoking from it, the filters, and the CSV shape.
class Training::MenteesControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include ActiveSupport::Testing::TimeHelpers

  YEAR = 2026
  SLUG = "green-dot"

  setup do
    travel_to Time.zone.local(YEAR, 8, 10, 12, 0, 0)
    Rails.cache.clear
    Current.reset

    Position.create!(id: Position::TRAINING, title: "Training",
                     type: Position::TYPE_TRAINING, active: true)
    @green_dot = Position.create!(id: Position::GREEN_DOT_TRAINING, title: "Green Dot Training",
                                  type: Position::TYPE_TRAINING, active: true)
    @sandman_training = Position.create!(id: Position::SANDMAN_TRAINING, title: "Sandman Training",
                                         type: Position::TYPE_TRAINING, active: true)
    @mentee = Position.create!(id: Position::GREEN_DOT_MENTEE, title: "Green Dot Mentee",
                               type: "Frontline", active: true)
    @sanctuary = Position.create!(id: Position::SANCTUARY_MENTEE, title: "Sanctuary Mentee",
                                  type: "Frontline", active: true)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::TRAINER, "Trainer")
    ensure_role(Role::ART_TRAINER_BASE | Position::GREEN_DOT_TRAINING, "Green Dot Interface")
    ensure_role(Role::ART_GRADUATE_BASE | Position::GREEN_DOT_TRAINING, "Green Dot Graduate")

    @admin = person(:auditor_ranger)
    @art_trainer = person(:retired_ranger)
    @dirt_trainer = person(:echelon_ranger)

    grant_role(@admin, Role::ADMIN)
    grant_role(@art_trainer, Role::ART_TRAINER_BASE | Position::GREEN_DOT_TRAINING)
    grant_role(@dirt_trainer, Role::TRAINER)

    @alpha = person(:active_ranger)
    @beta = person(:inactive_ranger)
  end

  teardown do
    Current.reset
    Rails.cache.clear
    travel_back
  end

  def grant(person_record, position, joined_on: nil)
    PersonPosition.create!(person_id: person_record.id, position_id: position.id)
    return unless joined_on

    PersonPositionLog.create!(person_id: person_record.id, position_id: position.id, joined_on:)
  end

  def rangered(person_record, position, on_duty)
    Timesheet.create!(person_id: person_record.id, position_id: position.id,
                      on_duty:, off_duty: on_duty + 4.hours, additional_notes: "test")
  end

  def get_report(**params) = get(training_mentees_path(SLUG, **params))

  # --- authorization -------------------------------------------------------

  test "the ART's interface role grants access" do
    grant(@alpha, @mentee)

    sign_in_as(@art_trainer)
    get_report

    assert_response :success
    assert_match "Current Mentees", response.body
    assert_match @alpha.callsign, response.body
  end

  test "an admin gets access" do
    sign_in_as(@admin)
    get_report

    assert_response :success
  end

  test "a plain Trainer is refused another ART's mentees" do
    sign_in_as(@dirt_trainer)
    get_report

    assert_redirected_to me_root_path
  end

  test "In-Person Training has no mentee positions" do
    sign_in_as(@admin)
    get training_mentees_path("in-person")

    assert_redirected_to training_path("in-person")
    assert_match(/does not have mentee positions/, flash[:error])
  end

  test "an ART without mentee positions has no report" do
    sign_in_as(@admin)
    get training_mentees_path("sandman")

    assert_redirected_to training_path("sandman")
  end

  # --- the roster ----------------------------------------------------------

  test "only people holding a mentee position are listed" do
    grant(@alpha, @mentee)

    sign_in_as(@admin)
    get_report

    assert_match @alpha.callsign, response.body
    assert_no_match(/#{Regexp.escape(@beta.callsign)}/, response.body)
    # Each row can be revoked from here, so this is a page the reader operates.
    assert_select "details summary", text: "How This Page Works", count: 1
  end

  test "an empty roster says so" do
    sign_in_as(@admin)
    get_report

    assert_match(/No one currently holds/, response.body)
  end

  # --- revoking ------------------------------------------------------------

  test "the interface role alone cannot revoke" do
    grant(@alpha, @mentee)

    sign_in_as(@art_trainer)
    get_report

    assert_no_match(/Revoke Positions/, response.body)
    assert_match(/Contact your cadre/, response.body)
  end

  test "the graduate role revokes every mentee position at once" do
    grant(@alpha, @mentee, joined_on: Time.zone.local(2024, 3, 1))
    grant(@alpha, @sanctuary, joined_on: Time.zone.local(2024, 3, 1))
    grant_role(@art_trainer, Role::ART_GRADUATE_BASE | Position::GREEN_DOT_TRAINING)

    sign_in_as(@art_trainer)
    delete training_revoke_mentee_positions_path(SLUG, @alpha.id)

    assert_redirected_to training_mentees_path(SLUG)
    assert_match(/revoked/, flash[:success])
    assert_empty PersonPosition.where(person_id: @alpha.id,
                                      position_id: [@mentee.id, @sanctuary.id])
    # The grant log is closed rather than deleted -- the history is the point.
    assert_equal 2, PersonPositionLog.where(person_id: @alpha.id).where.not(left_on: nil).count
  end

  test "revoking streams a replacement row that keeps the grant years" do
    grant(@alpha, @mentee, joined_on: Time.zone.local(2024, 3, 1))
    rangered(@alpha, @mentee, Time.zone.local(2025, 8, 30, 18, 0, 0))
    grant_role(@art_trainer, Role::ART_GRADUATE_BASE | Position::GREEN_DOT_TRAINING)

    sign_in_as(@art_trainer)
    delete training_revoke_mentee_positions_path(SLUG, @alpha.id),
           headers: { "Accept" => Mime[:turbo_stream].to_s }

    assert_response :success
    assert_equal Mime[:turbo_stream], response.media_type

    assert_match %r{<turbo-stream action="replace" target="mentee-row-#{@alpha.id}">}, response.body
    # The row records what was revoked, so the grant history stays readable.
    assert_match "Granted 2024", response.body
    assert_match "Rangered 2025", response.body
    assert_match "Positions revoked", response.body
    assert_no_match(/Revoke Positions</, response.body)
    # And the toast rides along on the same response.
    assert_match %r{<turbo-stream action="append" target="toast-container">}, response.body

    assert_empty PersonPosition.where(person_id: @alpha.id, position_id: @mentee.id)
  end

  test "the streamed row keeps the responsive labels of the table it lands in" do
    grant(@alpha, @mentee)
    grant_role(@art_trainer, Role::ART_GRADUATE_BASE | Position::GREEN_DOT_TRAINING)

    sign_in_as(@art_trainer)
    delete training_revoke_mentee_positions_path(SLUG, @alpha.id),
           headers: { "Accept" => Mime[:turbo_stream].to_s }

    # Same data-labels the index emits -- a standalone row has no thead to
    # learn them from, so ui_table_rows is handed the headings explicitly.
    assert_match 'data-label="Callsign"', response.body
    assert_match 'data-label="Green Dot Mentee"', response.body
    assert_match 'data-label="Action"', response.body
  end

  test "the index tags each row with the id the stream targets" do
    grant(@alpha, @mentee)

    sign_in_as(@admin)
    get_report

    assert_match %r{<tr id="mentee-row-#{@alpha.id}"}, response.body
  end

  test "a non-Turbo revoke still redirects to the roster" do
    grant(@alpha, @mentee)

    sign_in_as(@admin)
    delete training_revoke_mentee_positions_path(SLUG, @alpha.id)

    assert_redirected_to training_mentees_path(SLUG)
    assert_match(/revoked/, flash[:success])
  end

  test "revoking is refused without the graduate role" do
    grant(@alpha, @mentee)

    sign_in_as(@art_trainer)
    delete training_revoke_mentee_positions_path(SLUG, @alpha.id)

    assert_redirected_to me_root_path
    assert_equal 1, PersonPosition.where(person_id: @alpha.id, position_id: @mentee.id).count
  end

  test "someone who holds no mentee position cannot be revoked" do
    sign_in_as(@admin)
    delete training_revoke_mentee_positions_path(SLUG, @beta.id)

    assert_redirected_to training_mentees_path(SLUG)
    assert_match(/does not hold/, flash[:error])
  end

  # --- restoring -----------------------------------------------------------

  test "the revoked row offers to restore exactly what it took" do
    grant(@alpha, @mentee)
    grant_role(@art_trainer, Role::ART_GRADUATE_BASE | Position::GREEN_DOT_TRAINING)

    sign_in_as(@art_trainer)
    delete training_revoke_mentee_positions_path(SLUG, @alpha.id),
           headers: { "Accept" => Mime[:turbo_stream].to_s }

    assert_match "Restore Positions", response.body
    # Only the position they actually held rides along.
    assert_match "position_ids%5B%5D=#{@mentee.id}", response.body
    assert_no_match(/position_ids%5B%5D=#{@sanctuary.id}/, response.body)
  end

  test "restoring re-grants the positions and streams the ordinary row back" do
    grant(@alpha, @mentee)
    grant_role(@art_trainer, Role::ART_GRADUATE_BASE | Position::GREEN_DOT_TRAINING)
    PersonPosition.where(person_id: @alpha.id, position_id: @mentee.id).delete_all

    sign_in_as(@art_trainer)
    post training_restore_mentee_positions_path(SLUG, @alpha.id, position_ids: [@mentee.id]),
         headers: { "Accept" => Mime[:turbo_stream].to_s }

    assert_response :success
    assert_match %r{<turbo-stream action="replace" target="mentee-row-#{@alpha.id}">}, response.body
    assert_match "Revoke Positions", response.body
    assert_no_match(/Positions revoked/, response.body)
    assert_equal 1, PersonPosition.where(person_id: @alpha.id, position_id: @mentee.id).count
  end

  test "restoring re-grants rather than reopening the closed log row" do
    grant(@alpha, @mentee, joined_on: Time.zone.local(2024, 3, 1))
    grant_role(@art_trainer, Role::ART_GRADUATE_BASE | Position::GREEN_DOT_TRAINING)

    sign_in_as(@art_trainer)
    delete training_revoke_mentee_positions_path(SLUG, @alpha.id)
    post training_restore_mentee_positions_path(SLUG, @alpha.id, position_ids: [@mentee.id])

    logs = PersonPositionLog.where(person_id: @alpha.id, position_id: @mentee.id).order(:id)

    assert_equal 2, logs.size, "the revoke stays on the record"
    assert_equal Time.zone.local(2024, 3, 1).to_date, logs.first.joined_on.to_date
    assert_not_nil logs.first.left_on
    assert_equal YEAR, logs.last.joined_on.year
    assert_nil logs.last.left_on
  end

  test "restore cannot grant a position outside the training's mentee set" do
    outsider = Position.create!(id: Position::DIRT_GREEN_DOT, title: "Dirt - Green Dot",
                                type: "Frontline", active: true)
    grant_role(@art_trainer, Role::ART_GRADUATE_BASE | Position::GREEN_DOT_TRAINING)

    sign_in_as(@art_trainer)
    post training_restore_mentee_positions_path(SLUG, @alpha.id, position_ids: [outsider.id])

    assert_redirected_to training_mentees_path(SLUG)
    assert_match(/no .* mentee positions to restore/, flash[:error])
    assert_empty PersonPosition.where(person_id: @alpha.id, position_id: outsider.id)
  end

  # to_i read "#{id}x" as the id and re-granted that position.
  test "restore ignores position ids that are not ids" do
    grant_role(@art_trainer, Role::ART_GRADUATE_BASE | Position::GREEN_DOT_TRAINING)

    sign_in_as(@art_trainer)
    post training_restore_mentee_positions_path(SLUG, @alpha.id, position_ids: ["", "abc", "#{@mentee.id}x"])

    assert_redirected_to training_mentees_path(SLUG)
    assert_match(/no .* mentee positions to restore/, flash[:error])
    assert_empty PersonPosition.where(person_id: @alpha.id, position_id: @mentee.id)
  end

  test "restoring is refused without the graduate role" do
    sign_in_as(@art_trainer)
    post training_restore_mentee_positions_path(SLUG, @alpha.id, position_ids: [@mentee.id])

    assert_redirected_to me_root_path
    assert_empty PersonPosition.where(person_id: @alpha.id, position_id: @mentee.id)
  end

  # --- filters -------------------------------------------------------------

  test "the rangering filter separates never from stale" do
    grant(@alpha, @mentee)
    rangered(@alpha, @mentee, Time.zone.local(YEAR - 3, 8, 30, 18, 0, 0))
    grant(@beta, @mentee)

    sign_in_as(@admin)

    get_report(rangering: "never")

    assert_match @beta.callsign, response.body
    assert_no_match(/#{Regexp.escape(@alpha.callsign)}/, response.body)

    get_report(rangering: "stale")

    assert_match @alpha.callsign, response.body
    assert_no_match(/#{Regexp.escape(@beta.callsign)}/, response.body)
  end

  test "someone who rangered this year is neither never nor stale" do
    grant(@alpha, @mentee)
    rangered(@alpha, @mentee, Time.zone.local(YEAR, 8, 1, 18, 0, 0))

    sign_in_as(@admin)

    get_report(rangering: "never")

    assert_no_match(/#{Regexp.escape(@alpha.callsign)}/, response.body)

    get_report(rangering: "stale")

    assert_no_match(/#{Regexp.escape(@alpha.callsign)}/, response.body)
  end

  test "the callsign filter narrows the list" do
    grant(@alpha, @mentee)
    grant(@beta, @mentee)

    sign_in_as(@admin)
    get_report(callsign: @alpha.callsign.downcase)

    assert_match @alpha.callsign, response.body
    assert_no_match(/#{Regexp.escape(@beta.callsign)}/, response.body)
  end

  # --- export --------------------------------------------------------------

  test "the CSV carries two columns per position and ignores the filters" do
    grant(@alpha, @mentee, joined_on: Time.zone.local(2024, 3, 1))
    rangered(@alpha, @mentee, Time.zone.local(2025, 8, 30, 18, 0, 0))
    grant(@beta, @sanctuary)

    sign_in_as(@admin)
    get training_mentees_path(SLUG, format: :csv, callsign: @alpha.callsign)

    assert_response :success

    rows = response.body.split("\n")

    assert_equal "Callsign,Status,Green Dot Mentee Granted,Green Dot Mentee Last Rangered," \
                 "Sanctuary Mentee Granted,Sanctuary Mentee Last Rangered", rows.first
    assert_equal 3, rows.size, "the export is the whole roster, not the filtered view"
    assert_includes rows, "#{@alpha.callsign},#{@alpha.status},2024,2025,not granted,never"
    assert_includes rows, "#{@beta.callsign},#{@beta.status},not granted,never,unknown,never"
  end
end
