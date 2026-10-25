# frozen_string_literal: true

require "test_helper"

class Timesheets::OnDutyControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include EscapedMarkupTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include TrainingSlotTestHelper
  include ReportCardTestHelper # card_answer
  include ActiveSupport::Testing::TimeHelpers

  YEAR = 2031

  setup do
    Rails.cache.clear
    Current.reset

    @now = Time.zone.local(YEAR, 8, 26, 12, 0, 0)
    travel_to @now

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::EVENT_MANAGEMENT, "Event Management")
    ensure_role(Role::TIMESHEET_MANAGEMENT, "Timesheet Management")

    @admin = person(:active_ranger)
    @event_manager = person(:echelon_ranger)
    @outsider = person(:inactive_ranger)
    grant_role(@admin, Role::ADMIN)
    grant_role(@event_manager, Role::EVENT_MANAGEMENT)

    @ood = positions(:ood_position)
    @mentor = positions(:mentor_lead)

    sign_in_as(@admin)
  end

  teardown do
    travel_back
    Current.reset
    Rails.cache.clear
  end

  def create_timesheet(person, position, on_duty:, off_duty: nil, slot: nil)
    Timesheet.create!(person:, position:, on_duty:, off_duty:, slot:,
                      additional_notes: "test shift")
  end

  # Upstream's TimesheetPolicy::before grants Timesheet Management every method
  # on the policy, this report included.
  test "admin, event management, and timesheet management may all view the report" do
    timesheet_manager = @outsider
    grant_role(timesheet_manager, Role::TIMESHEET_MANAGEMENT)

    [@admin, @event_manager, timesheet_manager].each do |viewer|
      sign_in_as(viewer)
      get timesheets_on_duty_path
      assert_response :success, "#{viewer.callsign} should be allowed in"
    end
  end

  test "someone without the role is turned away" do
    sign_in_as(@outsider)

    get timesheets_on_duty_path

    assert_redirected_to me_root_path
  end

  test "the board lists who is on duty and says nothing when no one is" do
    get timesheets_on_duty_path
    assert_select "*", text: /No one is on duty right now/

    create_timesheet(@admin, @ood, on_duty: @now - 2.hours)

    get timesheets_on_duty_path
    assert_response :success
    assert_select "h2", text: @ood.title
    assert_select "a", text: @admin.callsign
    # The figure beside the callsign says what it is to a pointer, and the card
    # says the same words to everyone else.
    assert_select "span[title=?]", "Elapsed time on duty"
    assert_equal "Elapsed time on duty.", card_answer("What is the time beside each callsign?")
  end

  test "a flagged Ranger is called out above the board and the second line says how far over" do
    slot = create_slot(@ood, begins: @now - 4.hours, ends: @now - 2.hours) # 2 hours
    create_timesheet(@admin, @ood, on_duty: @now - 4.hours, slot:)

    get timesheets_on_duty_path

    assert_select "*", text: /Check On These Rangers/
    assert_select "*", text: /2:00 over \(\+100%\)/
    assert_select "*", text: /2:00 scheduled/
    # datetime_format hands back a <span>; interpolating it into the detail
    # line rather than joining it printed the markup on the page.
    assert_no_escaped_markup
  end

  test "a Ranger with no attached slot says so rather than showing a dash" do
    create_timesheet(@admin, @ood, on_duty: @now - 2.hours)

    get timesheets_on_duty_path

    assert_select "*", text: /no shift attached/
  end

  test "excessive_only narrows the board and round-trips as a filter chip" do
    create_timesheet(@event_manager, @mentor, on_duty: @now - 1.hour)
    create_timesheet(@admin, @ood, on_duty: @now - 10.hours)

    get timesheets_on_duty_path(excessive_only: "1")

    assert_response :success
    assert_select "h2", text: @ood.title
    assert_select "h2", { text: @mentor.title, count: 0 }
    assert_select "a", text: /Showing: Out longer than usual/
  end

  test "a point-in-time view keeps someone who is still out and marks them so" do
    at = @now - 6.hours
    create_timesheet(@admin, @ood, on_duty: at - 1.hour)

    get timesheets_on_duty_path(duty_date: at.strftime("%Y-%m-%d %H:%M"))

    assert_response :success
    assert_select "a", text: @admin.callsign
    assert_select "*", text: /still on duty/
  end

  # Each of these parses to *something* under Time.zone.parse's defaulting --
  # midnight today, the 3rd of this month -- which the page would then have
  # stated as fact. Only a whole calendar date is accepted.
  ["when the sun goes down", "the 3rd shift", "26", "202", "next tuesday at 3"].each do |bad|
    test "a duty date of #{bad.inspect} falls back to right now and says so" do
      create_timesheet(@admin, @ood, on_duty: @now - 2.hours)

      get timesheets_on_duty_path(duty_date: bad)

      assert_response :success
      assert_select "*", text: /Could not read/
      # Fell back rather than filtering, and the rejected value draws no chip.
      assert_select "a", text: @admin.callsign
      assert_select "a", { text: /As Of:/, count: 0 }
    end
  end

  test "the rejection is a warning, not a neutral notice" do
    get timesheets_on_duty_path(duty_date: "nope")

    assert_response :success
    assert flash.now[:warning].present?, "expected a :warning flash; :alert renders as blue info"
  end

  test "a duty date that is not a string falls back instead of raising" do
    create_timesheet(@admin, @ood, on_duty: @now - 2.hours)

    ["#{timesheets_on_duty_path}?duty_date[a]=b",
     "#{timesheets_on_duty_path}?duty_date[]=1&duty_date[]=2"].each do |url|
      get url

      assert_response :success, "#{url} should fall back, not 500"
      assert_select "a", text: @admin.callsign
    end
  end

  test "a readable duty date draws its chip" do
    at = @now - 6.hours
    create_timesheet(@admin, @ood, on_duty: at - 1.hour)

    get timesheets_on_duty_path(duty_date: at.strftime("%Y-%m-%d %H:%M"))

    # The absence assertions above are only worth something if the chip can
    # actually appear.
    assert_select "a", text: /As Of: #{Regexp.escape(at.strftime("%Y-%m-%d %H:%M"))}/
  end

  test "the filter checkbox label points at the field it labels" do
    get timesheets_on_duty_path

    checkbox_id = css_select("input[type=checkbox][name=excessive_only]").sole["id"]
    assert checkbox_id.present?
    assert_select "label[for=?]", checkbox_id
    # include_hidden: false -- a GET form must not carry the companion "0".
    assert_select "input[type=hidden][name=excessive_only]", count: 0
  end
end
