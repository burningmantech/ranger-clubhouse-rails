# frozen_string_literal: true

require "test_helper"

# The HQ twin of Person::SchedulingControllerTest. Most of the behaviour is
# inherited from ScheduleConcern and already covered there, so the assertions
# here concentrate on what is genuinely new in the HQ port:
#
#   * the year lock — the HQ shell has no year selector, so ?year= must be
#     ignored and the selector must not render;
#   * the promise that the window operator never leaves /hq, i.e. no page in
#     this namespace links back into /person or /me;
#   * the widened audience — Shift Management alone now reaches these pages,
#     where the old sidebar link-out demanded the person-page roles.
class Hq::SchedulingControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper

  setup do
    Rails.cache.clear
    Current.reset

    # The window operator deliberately holds Shift Management and nothing else.
    @viewer = person(:ranger_with_custom_gender)
    @subject = person(:active_ranger)
    @admin = person(:auditor_ranger)
    @past_year = Current.year - 1
    @position = positions(:training_lead)

    ensure_role(Role::ADMIN, "Admin")
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
    Rails.cache.clear
  end

  test "redirects away when the HQ Window Interface setting is off" do
    Setting.find_or_create_by(name: Setting::HQ_WINDOW_INTERFACE_ENABLED).update!(value: "false")

    get hq_scheduling_path(@subject)

    assert_redirected_to person_path(@subject)
  end

  test "requires the admin or shift management permission" do
    sign_in_as(@subject) # holds no roles at all

    get hq_scheduling_path(@viewer)

    assert_redirected_to me_root_path
  end

  # Decision 3: HQ scheduling is gated by HqConcern alone. The sidebar item it
  # replaces carried an extra person-page-roles gate, which was dropped.
  test "a shift management only operator reaches every HQ scheduling page" do
    assert_equal [Role::SHIFT_MANAGEMENT], @viewer.person_role.pluck(:role_id),
                 "the viewer must hold Shift Management and nothing else for this test to mean anything"

    [
      hq_scheduling_path(@subject),
      hq_scheduling_signup_summary_path(@subject),
      hq_scheduling_qualifications_path(@subject)
    ].each do |path|
      get path
      assert_response :success, "#{path} should be reachable with Shift Management alone"
    end
  end

  test "schedule index renders with hq scoped links" do
    get hq_scheduling_path(@subject)

    assert_response :success
    assert_select "#schedule-header", text: /Schedule \/ Sign-Ups/
    # Decision 2: the back link stays inside /hq and reads "Shift Check In/Out".
    assert_select "a[href='#{hq_shift_manage_path(@subject)}']", text: /Shift Check In\/Out/
    assert_select "a[href='#{hq_scheduling_sign_ups_path(@subject, year: Current.year)}']"
    assert_select "a[href='#{person_scheduling_path(@subject)}']", false,
                  "the HQ schedule page must not link out to the person namespace"
  end

  # Decision 1, half one: the selector markup is gone. year_selector /
  # year_selector_compact both emit a <select name="year">, under the ids
  # "year-selector" (mobile) and "year-selector-compact" (desktop).
  test "schedule index renders no year selector" do
    get hq_scheduling_path(@subject)

    assert_response :success
    assert_select "select[name=?]", "year", false
    assert_select "select#year-selector", false
    assert_select "select#year-selector-compact", false
    assert_no_match(/Year to view:/, @response.body)
  end

  # Decision 4, settled by looking at it: the HQ layout already wraps children in
  # a right-hand person/summary column, so common/schedule/index's own desktop
  # rail would make three columns beside the sidebar and wrap each shift row onto
  # three lines at ~1100px. sidebar_actions: false folds the same buttons into the
  # main column. The person contrast below keeps this from passing vacuously.
  test "schedule index folds the scheduling actions into the main column" do
    get hq_scheduling_path(@subject)

    assert_response :success
    assert_no_match(/Scheduling Actions/, @response.body)
    # The actions themselves must survive the fold, not vanish with the rail.
    assert_select "a[href='#{hq_scheduling_sign_ups_path(@subject, year: Current.year)}']"
    assert_select "a[href='#{hq_scheduling_export_path(@subject, format: :ics)}']"
    if @subject.can_work?
      assert_select "a[href='#{hq_scheduling_qualifications_path(@subject, year: Current.year)}']"
      assert_select "a[href='#{hq_scheduling_signup_summary_path(@subject, year: Current.year)}']"
    end
  end

  # The rail offered sign-ups to everyone; the button row that replaces it gated
  # them behind can_work?, which excludes Prospectives — a status an HQ operator
  # handles constantly during the event. Folding the rail must not cost them
  # their sign-up entry point. (Alphas ARE in WORKING_STATUSES, deliberately —
  # they walk shifts with a Mentor — so a Prospective is the real contrast here.)
  test "a prospective still gets the available sign-ups entry point at the hq window" do
    # update_column, not update!: Person#log_status_change fans out into
    # PersonStatusManagement position bookkeeping, and this test is only about
    # what the view renders for a non-working status.
    @subject.update_column(:status, Person::PROSPECTIVE)
    assert_not @subject.reload.can_work?, "fixture guard: Prospective must be outside WORKING_STATUSES"

    get hq_scheduling_path(@subject)

    assert_response :success
    assert_select "a[href='#{hq_scheduling_sign_ups_path(@subject, year: Current.year)}']", true,
                  "a Prospective must keep the Available Sign-ups link the side rail used to provide"
  end

  test "the person schedule page still renders the scheduling actions rail" do
    grant_role(@admin, Role::ADMIN)
    sign_in_as(@admin)

    get person_scheduling_path(@subject)

    assert_response :success
    assert_match(/Scheduling Actions/, @response.body)
  end

  # Decision 1, half two, and the only genuinely new behaviour in this port: a
  # ?year= is ignored outright rather than merely re-labelled. Proven with real
  # data — a past-year sign-up that the person page WOULD show (see the contrast
  # test below) stays invisible here.
  test "schedule index ignores a year parameter and stays on the current year" do
    past_slot, _current_slot = signed_up_slots_across_two_years

    get hq_scheduling_path(@subject, year: @past_year)

    assert_response :success
    assert_select "#schedule-header", text: /#{Current.year} Schedule \/ Sign-Ups/
    assert_includes @response.body, @position.title
    assert_not_includes @response.body, past_slot.position.title,
                        "a ?year= in the past must not pull past-year sign-ups into the HQ page"
    # The year the page hands onward is the current one, never the requested one.
    assert_select "a[href='#{hq_scheduling_sign_ups_path(@subject, year: Current.year)}']"
    assert_select "a[href='#{hq_scheduling_sign_ups_path(@subject, year: @past_year)}']", false
  end

  # Pins the two assertions above as non-vacuous: the same request against the
  # person namespace does honour ?year= and does render the selector.
  test "the person schedule page still honours year and renders the selector" do
    past_slot, _current_slot = signed_up_slots_across_two_years
    grant_role(@admin, Role::ADMIN)
    sign_in_as(@admin)

    get person_scheduling_path(@subject, year: @past_year)

    assert_response :success
    assert_select "#schedule-header", text: /#{@past_year} Schedule \/ Sign-Ups/
    assert_includes @response.body, past_slot.position.title
    assert_select "select[name=?]", "year"
  end

  test "signup summary renders with an hq scoped back link" do
    get hq_scheduling_signup_summary_path(@subject)

    assert_response :success
    assert_select "#hours-credits-header", text: /Hours & Credits/
    assert_select "a[href='#{hq_scheduling_path(@subject)}']", text: /Schedule/
    assert_select "a[href='#{person_scheduling_path(@subject)}']", false
  end

  # The view is shared by four namespaces; a /me link here would pull the operator
  # out of the window.
  test "qualifications renders with hq scoped back and sign-ups links" do
    get hq_scheduling_qualifications_path(@subject)

    assert_response :success
    assert_select "#qualifications-header", text: /Qualifications/
    assert_select "a[href='#{hq_scheduling_path(@subject)}']", text: /Schedule & Sign-Ups/
    assert_select "#qualifications-next-step a[href=?]", hq_scheduling_sign_ups_path(@subject)
  end

  # ScheduleConcern#signups renders partial: "people_signed_up" by BARE NAME,
  # which Rails resolves against Hq::SchedulingController's _prefixes rather
  # than against common/. Without app/views/hq/scheduling/_people_signed_up this
  # raises MissingTemplate — the same trap that broke the person namespace.
  test "signups action renders the people signed up partial in the hq namespace" do
    slot = create_slot(@position, begins: 2.days.from_now)
    PersonPosition.find_or_create_by!(person: @subject, position: @position)
    PersonSlot.create!(person: @subject, slot:)

    get hq_scheduling_signups_path(@subject, slot_id: slot.id)

    assert_response :success
    assert_includes @response.body, @subject.callsign
  end

  test "export streams an ics calendar" do
    slot = create_slot(@position, begins: 2.days.from_now)
    PersonPosition.find_or_create_by!(person: @subject, position: @position)
    PersonSlot.create!(person: @subject, slot:)

    get hq_scheduling_export_path(@subject, format: :ics)

    assert_response :success
    assert_equal "text/calendar", @response.media_type
    assert_includes @response.body, "BEGIN:VCALENDAR"
  end

  test "destroy removes the sign-up and redirects back inside hq" do
    slot = create_slot(@position, begins: 2.days.from_now)
    PersonPosition.find_or_create_by!(person: @subject, position: @position)
    PersonSlot.create!(person: @subject, slot:)

    delete hq_scheduling_destroy_path(@subject, slot_id: slot.id)

    assert_redirected_to hq_scheduling_path(@subject, year: Current.year)
    assert_not PersonSlot.have_slot?(@subject.id, slot.id)
  end

  # The HQ shell chrome and the shared common/schedule/signup_summary body both
  # want a "summary": the column's is what the Ranger has WORKED, the page's is
  # what they have SIGNED UP FOR. They collide unless the shell keeps its own
  # ivar name, and the collision is silent rather than loud —
  # Scheduling::Summaries::ScheduleSummary answers both members
  # HqConcern::TimesheetSummary defines, in the same units, so the column would
  # render the sign-up estimate under its "Earned Credits" label instead of
  # raising. Hence @hq_summary in HqConcern.
  test "the hours and credits page leaves the shell column showing worked figures" do
    schedule_six_hours_at_two_credits_per_hour

    get hq_scheduling_path(@subject)
    assert_response :success
    baseline = hq_summary_column
    assert_equal({ credits: "zero credits", hours: "0 mins" }, baseline,
                 "the subject has worked no shifts this year, so the column must read zero")

    get hq_scheduling_signup_summary_path(@subject)
    assert_response :success

    # Non-vacuous: the page body really is reporting the larger scheduled
    # figures that the column must NOT pick up.
    assert_select "#hours-credits-header"
    assert_includes @response.body, "12.00 credits"
    assert_includes @response.body, "6 hours 0 mins"

    assert_equal baseline, hq_summary_column,
                 "the shell column must keep reporting worked hours and earned credits, " \
                 "not the sign-up estimates the page body shows"
  end

  test "no hq scheduling page links out of the hq namespace" do
    get hq_scheduling_path(@subject)
    assert_no_escape_hatches "schedule-header"

    get hq_scheduling_signup_summary_path(@subject)
    assert_no_escape_hatches "hours-credits-header"

    get hq_scheduling_qualifications_path(@subject)
    assert_no_escape_hatches "qualifications-header"
  end

  private

  # The two figures the persistent HQ shell column renders, as displayed.
  def hq_summary_column
    document = Nokogiri::HTML(@response.body)
    {
      credits: document.at_css("#hq-earned-credits")&.text&.strip,
      hours: document.at_css("#hq-worked-hours")&.text&.strip
    }
  end

  # One 6-hour current-year sign-up inside the event week at 2 credits/hour, so
  # the SCHEDULED summary reads 6 hours / 12.00 credits while the subject's
  # WORKED summary stays at zero (the timesheet fixtures give active_ranger
  # nothing in the current year). Event dates are required for the schedule
  # summary to bucket the hours into counted_duration rather than "other".
  def schedule_six_hours_at_two_credits_per_hour
    year = Current.year
    EventDate.create!(
      event_start: Time.zone.local(year, 8, 25, 0, 0, 0),
      event_end: Time.zone.local(year, 9, 1, 0, 0, 0),
      pre_event_start: Time.zone.local(year, 8, 10, 0, 0, 0),
      pre_event_slot_start: Time.zone.local(year, 8, 10, 0, 0, 0),
      pre_event_slot_end: Time.zone.local(year, 8, 25, 0, 0, 0),
      post_event_end: Time.zone.local(year, 9, 10, 0, 0, 0)
    )
    PositionCredit.create!(
      position: @position,
      start_time: Time.zone.local(year, 8, 1, 0, 0, 0),
      end_time: Time.zone.local(year, 9, 30, 0, 0, 0),
      credits_per_hour: 2.0,
      description: "Event week"
    )

    slot = create_slot(@position, begins: Time.zone.local(year, 8, 26, 10, 0, 0))
    PersonPosition.find_or_create_by!(person: @subject, position: @position)
    PersonSlot.create!(person: @subject, slot:)
    slot
  end

  def create_slot(position, begins:, hours: 6)
    Slot.create!(
      position:,
      begins:,
      ends: begins + hours.hours,
      max: 10,
      active: true,
      timezone: "America/Los_Angeles"
    )
  end

  # One sign-up in the previous year (under a position with a distinctive title,
  # so its presence is unambiguous in the rendered body) and one in the current
  # year. Returns [past_slot, current_slot].
  def signed_up_slots_across_two_years
    past_position = Position.create!(title: "Past Year Only Position", active: true)
    PersonPosition.find_or_create_by!(person: @subject, position: past_position)
    PersonPosition.find_or_create_by!(person: @subject, position: @position)

    past_slot = create_slot(past_position, begins: Time.zone.local(@past_year, 8, 25, 8, 0, 0))
    current_slot = create_slot(@position, begins: 2.days.from_now)

    PersonSlot.create!(person: @subject, slot: past_slot)
    PersonSlot.create!(person: @subject, slot: current_slot)

    [past_slot, current_slot]
  end

  # A whole-body scan would be vacuous here: the HQ shell chrome legitimately
  # points at /person — the header carries a "Switch to Person Manage"
  # affordance. (The sidebar no longer does: its last link-out was absorbed
  # in-shell on 2026-07-22.) So the guard is scoped to the region the child
  # page renders into: the parent
  # of the page's own hero panel, i.e. the content column in
  # app/views/hq/shared/_shell.html.erb.
  def assert_no_escape_hatches(header_id)
    panel = Nokogiri::HTML(@response.body)
                    .at_css("section.me-hero-panel[aria-labelledby='#{header_id}']")
    assert panel, "expected the page to render a hero panel labelled ##{header_id}"

    region = panel.parent
    content = region.to_html
    # Guard the guard: if the shell ever wraps the page so that we scope down to
    # the hero panel alone, this check must fail loudly rather than pass on an
    # empty region.
    assert_operator content.length, :>, panel.to_html.length,
                    "expected to scope to the shell content column, not the hero panel alone"

    assert_no_match %r{href="/person/}, content,
                    "page content below ##{header_id} links out to the person namespace"
    assert_no_match %r{href="/me/}, content,
                    "page content below ##{header_id} links out to the me namespace"
  end
end
