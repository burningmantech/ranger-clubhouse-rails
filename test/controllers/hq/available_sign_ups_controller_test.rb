# frozen_string_literal: true

require "test_helper"

# The HQ twin of the available sign-ups half of Person::SchedulingControllerTest.
# Unlike the person namespace, HQ is pinned to the current year, so every request
# here runs the current-year signup requirements gate in
# AvailableSignUpsConcern#retrieve_permission_and_recommendation — the setup
# below clears the subject's outstanding requirement so the pages are reachable.
class Hq::AvailableSignUpsControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper

  setup do
    Rails.cache.clear
    Current.reset

    # The window operator deliberately holds Shift Management and nothing else.
    @viewer = person(:ranger_with_custom_gender)
    @subject = person(:active_ranger)
    @past_year = Current.year - 1
    @position = positions(:training_lead)

    ensure_role(Role::SHIFT_MANAGEMENT, "Shift Management")
    grant_role(@viewer, Role::SHIFT_MANAGEMENT)

    # The HQ shell loads PersonEventInfo, whose training lookup falls back to
    # Position.find(Position::TRAINING) — the fixtures do not pin that id.
    Position.find_or_create_by!(id: Position::TRAINING) do |position|
      position.title = "In-Person Training"
      position.type = Position::TYPE_TRAINING
      position.active = true
    end

    # Scheduling::Permission wants an approved callsign, a bpguid, and an
    # approved photo. The fixture already carries the first two.
    PersonPhoto.create!(person: @subject, status: PersonPhoto::APPROVED,
                        image_filename: "", orig_filename: "", profile_filename: "")
    PersonPosition.find_or_create_by!(person: @subject, position: @position)

    @slot = create_slot(@position, begins: 2.days.from_now)

    sign_in_as(@viewer)
  end

  teardown do
    Current.reset
    Rails.cache.clear
  end

  test "redirects away when the HQ Window Interface setting is off" do
    Setting.find_or_create_by(name: Setting::HQ_WINDOW_INTERFACE_ENABLED).update!(value: "false")

    get hq_scheduling_sign_ups_path(@subject)

    assert_redirected_to person_path(@subject)
  end

  test "requires the admin or shift management permission" do
    sign_in_as(@subject) # holds no roles at all

    get hq_scheduling_sign_ups_path(@viewer)

    assert_redirected_to me_root_path
  end

  # Decision 3: HqConcern is the whole gate. Shift Management alone must open
  # both the position list and an individual position's shifts.
  test "a shift management only operator reaches both available sign-ups pages" do
    assert_equal [Role::SHIFT_MANAGEMENT], @viewer.person_role.pluck(:role_id),
                 "the viewer must hold Shift Management and nothing else for this test to mean anything"

    get hq_scheduling_sign_ups_path(@subject)
    assert_response :success

    get hq_scheduling_sign_ups_position_path(@subject, @position.id)
    assert_response :success
  end

  test "index renders with hq scoped links" do
    get hq_scheduling_sign_ups_path(@subject)

    assert_response :success
    assert_select "#available-sign-ups-header", text: /Available Sign-Ups/
    assert_select "a[href='#{hq_scheduling_path(@subject)}']", text: /Schedule/
    assert_select "a[href='#{hq_scheduling_sign_ups_position_path(@subject, @position.id)}']"
    assert_select "a[href='#{person_scheduling_sign_ups_position_path(@subject, position_id: @position.id)}']",
                  false, "the HQ sign-ups list must not link out to the person namespace"
  end

  test "show renders the position shifts with hq scoped links" do
    get hq_scheduling_sign_ups_position_path(@subject, @position.id)

    assert_response :success
    assert_select "#position-shifts-header", text: /#{@position.title} Shifts/
    assert_select "turbo-frame##{ActionView::RecordIdentifier.dom_id(@slot)}"
    assert_select "a[href='#{hq_scheduling_sign_ups_path(@subject)}']", text: /Available Sign-Ups/
    assert_select "a[href='#{person_scheduling_sign_ups_path(@subject)}']", false
  end

  test "show prints the header for the member's status, not the operator's" do
    @position.update!(ranger_scheduling_header: "<p>Bring water</p>", applicant_scheduling_header: "<p>Welcome</p>")
    # An auditor gets no header at all (Position#scheduling_header_for), so a
    # lookup keyed on the operator would print nothing where the Ranger's note belongs.
    operator = person(:auditor_ranger)
    grant_role(operator, Role::SHIFT_MANAGEMENT)
    sign_in_as(operator)

    get hq_scheduling_sign_ups_position_path(@subject, @position.id)

    assert_response :success
    assert_select ".lexxy-content", text: /Bring water/
    assert_select ".lexxy-content", text: /Welcome/, count: 0
  end

  # Decision 1: a ?year= is ignored, not honoured. Proven with data — the
  # position that only exists in the past year stays out of the list.
  test "index ignores a year parameter and stays on the current year" do
    past_position = Position.create!(title: "Past Year Only Position", active: true)
    PersonPosition.find_or_create_by!(person: @subject, position: past_position)
    create_slot(past_position, begins: Time.zone.local(@past_year, 8, 25, 8, 0, 0))

    get hq_scheduling_sign_ups_path(@subject, year: @past_year)

    assert_response :success
    assert_select "#available-sign-ups-header", text: /Available Sign-Ups/
    assert_includes @response.body, @position.title
    assert_not_includes @response.body, "Past Year Only Position"
  end

  test "show ignores a year parameter and lists only current year shifts" do
    past_slot = create_slot(@position, begins: Time.zone.local(@past_year, 8, 25, 8, 0, 0))

    get hq_scheduling_sign_ups_position_path(@subject, @position.id, year: @past_year)

    assert_response :success
    assert_select "#position-shifts-header", text: /#{Current.year} #{@position.title} Shifts/
    assert_select "turbo-frame##{ActionView::RecordIdentifier.dom_id(@slot)}"
    assert_select "turbo-frame##{ActionView::RecordIdentifier.dom_id(past_slot)}", false,
                  "a ?year= in the past must not pull past-year shifts into the HQ page"
  end

  test "available sign-ups pages render no year selector" do
    [
      hq_scheduling_sign_ups_path(@subject),
      hq_scheduling_sign_ups_position_path(@subject, @position.id)
    ].each do |path|
      get path

      assert_response :success
      assert_select "select[name=?]", "year", false
      assert_select "select#year-selector", false
      assert_select "select#year-selector-compact", false
    end
  end

  test "signing up for a shift answers with a turbo stream and records the sign-up" do
    post hq_scheduling_sign_ups_slot_path(@subject, position_id: @position.id, slot_id: @slot.id),
         as: :turbo_stream

    assert_response :success
    assert PersonSlot.have_slot?(@subject.id, @slot.id),
           "the sign-up should be recorded for the subject person, not the operator"
    assert_not PersonSlot.have_slot?(@viewer.id, @slot.id)
  end

  test "removing a sign-up answers with a turbo stream and clears the sign-up" do
    PersonSlot.create!(person: @subject, slot: @slot)

    delete hq_scheduling_sign_ups_slot_path(@subject, position_id: @position.id, slot_id: @slot.id),
           as: :turbo_stream

    assert_response :success
    assert_not PersonSlot.have_slot?(@subject.id, @slot.id)
  end

  # A trainee shift's capacity is its max times the trainer slot's sign-ups
  # (Scheduling::SlotCapacity), so until a trainer signs up it holds no seats and
  # its card has no availability to report -- Clubhouse 2 showed a dash. Deciding
  # that raised NoMethodError (ScheduleEntry#zero?) and took the whole page down.
  test "show leaves availability off a trainer-bound slot until a trainer has signed up" do
    bound = create_trainer_bound_slot(trainers_signed_up: 0)

    get hq_scheduling_sign_ups_position_path(@subject, @position.id)

    assert_response :success
    card = slot_card(bound)
    assert_includes card.text, @position.title
    assert_no_match(/open spots?|spots taken/, card.text)
  end

  test "show reports availability on a trainer-bound slot once trainers have signed up" do
    bound = create_trainer_bound_slot(trainers_signed_up: 2)

    get hq_scheduling_sign_ups_position_path(@subject, @position.id)

    assert_response :success
    assert_includes slot_card(bound).text, "20 open spots of 20"
  end

  # The Add to Schedule button, the seat count and Signup.add all read one number --
  # Scheduling::SlotCapacity#effective_max -- so the button must not be judged against
  # the slot's raw max. With no trainer signed up the server answers "the shift has become
  # full"; the button must not invite that click. The plain slot is the selector's control:
  # without it a mistyped selector would make every absence assertion pass.
  test "show offers no Add to Schedule on a trainer-bound slot until a trainer has signed up" do
    bound = create_trainer_bound_slot(trainers_signed_up: 0)

    get hq_scheduling_sign_ups_position_path(@subject, @position.id)

    assert_response :success
    assert_select slot_card(bound), "a", { text: /Add to Schedule/, count: 0 },
                  "no trainer is signed up, so the slot holds no seats and cannot be added to"
    assert_select slot_card(@slot), "a", { text: /Add to Schedule/ },
                  "the open plain slot on the same page still offers it"
  end

  # Two trainers make room for 2 x 10 = 20 trainees. Ten signed up is the slot's raw max,
  # not its limit, so the card counts ten seats open and the button has to stay.
  test "show offers Add to Schedule on a trainer-bound slot with seats left at its raw max" do
    bound = create_trainer_bound_slot(trainers_signed_up: 2, signed_up: 10)

    get hq_scheduling_sign_ups_position_path(@subject, @position.id)

    assert_response :success
    card = slot_card(bound)
    assert_includes card.text, "10 open spots of 20"
    assert_select card, "a", { text: /Add to Schedule/ },
                  "ten of twenty seats are taken, so the slot can still be added to"
  end

  test "show offers no Add to Schedule on a full slot, trainer-bound or plain" do
    full_bound = create_trainer_bound_slot(trainers_signed_up: 2, signed_up: 20)
    full_plain = create_slot(@position, begins: 5.days.from_now, signed_up: 10)

    get hq_scheduling_sign_ups_position_path(@subject, @position.id)

    assert_response :success
    [full_bound, full_plain].each do |full|
      assert_select slot_card(full), "a", { text: /Add to Schedule/, count: 0 },
                    "slot ##{full.id} has no seat left"
    end
  end

  # The real Signup.add refuses a second Alpha sign-up, and the shared concern answers
  # with the modal. The operator is not the one enrolled, so it must name the subject.
  test "a second Alpha sign-up answers with the already signed up modal naming the subject" do
    alpha = Position.find_or_initialize_by(id: Position::ALPHA)
    alpha.update!(title: "Alpha", prevent_multiple_enrollments: true,
                  contact_email: "alpha-mentors@example.org")
    PersonPosition.find_or_create_by!(person: @subject, position: alpha)
    enrolled = create_slot(alpha, begins: 2.days.from_now, description: "Alpha Shift One")
    PersonSlot.create!(person: @subject, slot: enrolled)
    refused = create_slot(alpha, begins: 3.days.from_now)

    post hq_scheduling_sign_ups_slot_path(@subject, position_id: alpha.id, slot_id: refused.id),
         as: :turbo_stream

    assert_response :success
    assert_includes @response.body, "Already Signed Up"
    assert_includes @response.body, "Only one Alpha shift may be signed up for."
    assert_includes @response.body, "#{@subject.callsign} is already signed up"
    assert_includes @response.body, "Alpha Shift One"
    assert_includes @response.body, "alpha-mentors@example.org"
    assert_not PersonSlot.have_slot?(@subject.id, refused.id)
  end

  test "no hq available sign-ups page links out of the hq namespace" do
    get hq_scheduling_sign_ups_path(@subject)
    assert_no_escape_hatches "available-sign-ups-header"

    get hq_scheduling_sign_ups_position_path(@subject, @position.id)
    assert_no_escape_hatches "position-shifts-header"
  end

  private

  def create_slot(position, begins:, hours: 6, **attrs)
    Slot.create!(
      position:,
      begins:,
      ends: begins + hours.hours,
      max: 10,
      active: true,
      timezone: "America/Los_Angeles",
      **attrs
    )
  end

  def create_trainer_bound_slot(trainers_signed_up:, **attrs)
    trainer_slot = create_slot(@position, begins: 3.days.from_now, signed_up: trainers_signed_up)
    create_slot(@position, begins: 4.days.from_now, trainer_slot_id: trainer_slot.id, **attrs)
  end

  def slot_card(slot)
    frame = css_select("turbo-frame##{ActionView::RecordIdentifier.dom_id(slot)}").first
    assert frame, "expected the page to render slot ##{slot.id}"
    frame
  end

  # See Hq::SchedulingControllerTest for why this is scoped to the content
  # column rather than run over the whole response body.
  def assert_no_escape_hatches(header_id)
    panel = Nokogiri::HTML(@response.body)
                    .at_css("section.me-hero-panel[aria-labelledby='#{header_id}']")
    assert panel, "expected the page to render a hero panel labelled ##{header_id}"

    content = panel.parent.to_html
    assert_operator content.length, :>, panel.to_html.length,
                    "expected to scope to the shell content column, not the hero panel alone"

    assert_no_match %r{href="/person/}, content,
                    "page content below ##{header_id} links out to the person namespace"
    assert_no_match %r{href="/me/}, content,
                    "page content below ##{header_id} links out to the me namespace"
  end
end
