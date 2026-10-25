# frozen_string_literal: true

require "test_helper"

# The HQ twin of the /me timesheet pages. The shared behaviour lives in
# TimesheetConcern / TimesheetCorrectionsConcern and is exercised through the
# /me suite, so the assertions here concentrate on what is genuinely new:
#
#   * the widened audience — Shift Management alone drives the person's
#     self-serve corrections flow, where the sidebar link-out it replaces
#     demanded Admin / Event Management / Timesheet Management;
#   * corrections are ALWAYS on at the window — the TIMESHEET_CORRECTION_ENABLE
#     setting is deliberately not consulted;
#   * the year lock — ?year= is ignored, no year selector renders;
#   * no final confirmation step — verifying the last entry lands back on the
#     HQ entries list, never on the /me attestation page;
#   * the /me status gate is mirrored onto the person at the window;
#   * the operator never leaves /hq.
class Hq::TimesheetsControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include ActiveSupport::Testing::TimeHelpers
  include TimesheetAdminTestHelper

  setup do
    travel_to Time.zone.local(2026, 8, 30, 12, 0, 0)
    Rails.cache.clear
    Current.reset

    @viewer = person(:active_ranger)
    @subject = person(:ranger_with_custom_gender)
    @position = positions(:khaki_supervisor)

    ensure_role(Role::SHIFT_MANAGEMENT, "Shift Management")
    grant_role(@viewer, Role::SHIFT_MANAGEMENT)

    # The HQ shell loads PersonEventInfo, whose training lookup falls back to
    # Position.find(Position::TRAINING) — the fixtures do not pin that id.
    Position.find_or_create_by!(id: Position::TRAINING) do |position|
      position.title = "In-Person Training"
      position.type = Position::TYPE_TRAINING
      position.active = true
    end

    sign_in_as(@viewer)
  end

  teardown do
    Current.reset
    travel_back
    Rails.cache.clear
  end

  # --- Access gates ----------------------------------------------------------

  test "redirects away when the HQ Window Interface setting is off" do
    Setting.find_or_create_by(name: Setting::HQ_WINDOW_INTERFACE_ENABLED).update!(value: "false")

    get hq_timesheets_path(@subject)

    assert_redirected_to person_path(@subject)
  end

  test "requires the admin or shift management permission" do
    sign_in_as(@subject) # holds no roles at all

    get hq_timesheets_path(@viewer)

    assert_redirected_to me_root_path
  end

  test "a shift management only operator reaches every HQ timesheet page" do
    assert_equal [Role::SHIFT_MANAGEMENT], @viewer.person_role.pluck(:role_id),
                 "the viewer must hold Shift Management and nothing else for this test to mean anything"
    create_event_dates

    [
      hq_timesheets_path(@subject),
      event_summary_hq_timesheets_path(@subject)
    ].each do |path|
      get path
      assert_response :success, "#{path} should be reachable with Shift Management alone"
    end
  end

  # The /me pages are status-gated to active/Echelon people; the HQ twin
  # mirrors that gate onto the person at the window, not the operator.
  test "a non active subject is turned away but stays inside the hq shell" do
    # update_column, not update!: Person#log_status_change fans out into
    # PersonStatusManagement bookkeeping this test does not care about.
    @subject.update_column(:status, Person::ALPHA)

    get hq_timesheets_path(@subject)

    assert_redirected_to hq_shift_manage_path(@subject)
    assert_match(/does not have an active status/, flash[:error])
  end

  # --- Corrections always on -------------------------------------------------

  test "correction actions render even with the corrections setting off" do
    assert_nil Setting.find_by(name: Setting::TIMESHEET_CORRECTION_ENABLE),
               "fixture guard: the corrections setting must be absent (off) for this test to mean anything"
    entry = create_timesheet!(review_status: Timesheet::STATUS_UNVERIFIED)

    get hq_timesheets_path(@subject)

    assert_response :success
    assert_select "a[href='#{edit_hq_timesheet_path(@subject, entry)}']", text: /Request Correction/
    assert_select "a[href='#{mark_verified_hq_timesheet_path(@subject, entry)}']", text: /Mark as Verified/
  end

  test "the me page hides the correction actions when the setting is off" do
    entry = create_timesheet!(review_status: Timesheet::STATUS_UNVERIFIED, person: @subject)
    sign_in_as(@subject)

    get me_timesheet_dashboard_path

    assert_response :success
    assert_select "a[href='#{edit_me_timesheet_path(entry)}']", false,
                  "/me must keep honouring TIMESHEET_CORRECTION_ENABLE, or the HQ contrast above is vacuous"
  end

  # --- Year lock ---------------------------------------------------------------

  test "index ignores a year parameter and renders no year selector" do
    past_position = Position.create!(title: "Past Year Only Position", active: true)
    create_timesheet!(review_status: Timesheet::STATUS_VERIFIED, position: past_position,
                      on_duty: Time.zone.local(2025, 8, 28, 10, 0, 0),
                      off_duty: Time.zone.local(2025, 8, 28, 16, 0, 0))
    create_timesheet!(review_status: Timesheet::STATUS_UNVERIFIED)

    get hq_timesheets_path(@subject, year: 2025)

    assert_response :success
    assert_select "#timesheet-header", text: /#{Current.year} Timesheet/
    assert_includes @response.body, @position.title
    assert_not_includes @response.body, "Past Year Only Position",
                        "a ?year= in the past must not pull past-year entries into the HQ page"
    assert_select "select[name=?]", "year", false
  end

  # --- Voice and shell integrity ----------------------------------------------

  test "index reads in the third person and offers only the hq features" do
    create_timesheet!(review_status: Timesheet::STATUS_UNVERIFIED)

    get hq_timesheets_path(@subject)

    assert_response :success
    assert_match(/Review #{@subject.callsign}'s recorded hours/, @response.body)
    assert_select "a[href='#{hq_missing_requests_path(@subject)}']"
    assert_select "a[href='#{event_summary_hq_timesheets_path(@subject)}']"
    # Qualifications and work history remain /me-only features.
    assert_no_match(/Qualifications/, @response.body)
    assert_no_match(/Work History/, @response.body)
    assert_no_escape_hatches "timesheet-header"
  end

  test "correction form renders in the third person inside the shell" do
    entry = create_timesheet!(review_status: Timesheet::STATUS_UNVERIFIED)

    get edit_hq_timesheet_path(@subject, entry)

    assert_response :success
    assert_match(/Who was #{@subject.callsign}'s shift partner/, @response.body)
    assert_select "form[action='#{hq_timesheet_path(@subject, entry)}']"
    assert_no_escape_hatches "submit-correction-header"
  end

  # --- Verify ------------------------------------------------------------------

  test "mark verified updates the entry in place while others remain unverified" do
    entry = create_timesheet!(review_status: Timesheet::STATUS_UNVERIFIED)
    create_timesheet!(review_status: Timesheet::STATUS_UNVERIFIED,
                      on_duty: Time.zone.local(2026, 8, 29, 10, 0, 0),
                      off_duty: Time.zone.local(2026, 8, 29, 16, 0, 0))

    patch mark_verified_hq_timesheet_path(@subject, entry), as: :turbo_stream

    assert_response :success
    assert_equal Timesheet::STATUS_VERIFIED, entry.reload.review_status
    assert_select "turbo-stream[action='update'][target='entry-#{entry.id}']"
  end

  test "verifying the last entry lands back on the hq list, never on final confirmation" do
    entry = create_timesheet!(review_status: Timesheet::STATUS_UNVERIFIED)

    patch mark_verified_hq_timesheet_path(@subject, entry), as: :turbo_stream

    assert_response :success
    assert_equal Timesheet::STATUS_VERIFIED, entry.reload.review_status
    assert_select "turbo-stream[action='page_redirect'][url='#{hq_timesheets_path(@subject)}']"
    assert_no_match final_confirmation_me_timesheet_index_path, @response.body,
                    "the /me final confirmation step must not exist at the HQ window"
  end

  test "the me flow still continues into final confirmation" do
    Setting.find_or_create_by(name: Setting::TIMESHEET_CORRECTION_ENABLE).update!(value: "true")
    entry = create_timesheet!(review_status: Timesheet::STATUS_UNVERIFIED, person: @subject)
    sign_in_as(@subject)

    patch mark_verified_me_timesheet_path(entry), as: :turbo_stream

    assert_response :success
    assert_select "turbo-stream[action='page_redirect'][url='#{final_confirmation_me_timesheet_index_path}']"
  end

  # --- Correct -----------------------------------------------------------------

  test "submitting a correction marks the entry pending and stays inside hq" do
    entry = create_timesheet!(review_status: Timesheet::STATUS_UNVERIFIED)

    patch hq_timesheet_path(@subject, entry), params: {
      timesheet: {
        desired_position_id: "",
        desired_on_duty: "2026-08-28T09:00",
        desired_off_duty: "2026-08-28T16:00",
        additional_notes: "Started an hour early; corroborated by Shift Lead Slats."
      }
    }

    assert_redirected_to hq_timesheets_path(@subject)
    assert_equal Timesheet::STATUS_PENDING, entry.reload.review_status
  end

  # --- Hours & credits breakdown -------------------------------------------------

  test "event summary renders the third person breakdown" do
    create_event_dates
    create_timesheet!(review_status: Timesheet::STATUS_VERIFIED)

    get event_summary_hq_timesheets_path(@subject)

    assert_response :success
    assert_select "#event-summary-header", text: /Hours & Credits/
    assert_match(/Breakdown of #{@subject.callsign}(?:'|&#39;)s/, @response.body)
    assert_no_escape_hatches "event-summary-header"
  end

  private

  def create_timesheet!(review_status:,
                        person: @subject,
                        position: @position,
                        on_duty: Time.zone.local(2026, 8, 28, 10, 0, 0),
                        off_duty: Time.zone.local(2026, 8, 28, 16, 0, 0))
    entry = Timesheet.new(person_id: person.id, position_id: position.id,
                          on_duty:, off_duty:, review_status:)
    entry.save!(validate: false)
    entry
  end

  # EventSummaryReport buckets hours by event period, so it needs the year's
  # event dates to exist.
  def create_event_dates
    EventDate.create!(
      event_start: Time.zone.local(2026, 8, 25, 0, 0, 0),
      event_end: Time.zone.local(2026, 9, 1, 0, 0, 0),
      pre_event_start: Time.zone.local(2026, 8, 10, 0, 0, 0),
      pre_event_slot_start: Time.zone.local(2026, 8, 10, 0, 0, 0),
      pre_event_slot_end: Time.zone.local(2026, 8, 25, 0, 0, 0),
      post_event_end: Time.zone.local(2026, 9, 10, 0, 0, 0)
    )
  end

  # Same guard as the HQ scheduling suite: the shell chrome legitimately links
  # to /person, so the scan is scoped to the content column the page renders
  # into (the parent of its hero panel).
  def assert_no_escape_hatches(header_id)
    panel = Nokogiri::HTML(@response.body)
                    .at_css("section.me-hero-panel[aria-labelledby='#{header_id}']")
    assert panel, "expected the page to render a hero panel labelled ##{header_id}"

    region = panel.parent
    content = region.to_html
    assert_operator content.length, :>, panel.to_html.length,
                    "expected to scope to the shell content column, not the hero panel alone"

    assert_no_match %r{href="/person/}, content,
                    "page content below ##{header_id} links out to the person namespace"
    assert_no_match %r{href="/me/}, content,
                    "page content below ##{header_id} links out to the me namespace"
  end
end
