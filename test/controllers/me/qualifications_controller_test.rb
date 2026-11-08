# frozen_string_literal: true

require "test_helper"

class Me::QualificationsControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper

  setup do
    @person = person(:active_ranger)
    sign_in_as(@person)
    # Before event week, so every unearned row can still be earned by signing up.
    travel_to Time.zone.local(Current.year, 7, 1, 12)
  end

  test "index requires authentication" do
    sign_out

    get me_schedule_qualifications_url
    assert_redirected_to root_path
  end

  test "index renders qualifications page for authenticated person" do
    get me_schedule_qualifications_url(year: Current.year)

    assert_response :success
    assert_select "#qualifications-header", text: /Qualifications/
    assert_select "a[href='#{me_schedule_path(year: Current.year)}']", text: /#{Current.year} Schedule & Sign-Ups/
  end

  test "timesheet route renders qualifications page for authenticated person" do
    get me_timesheet_dashboard_qualifications_url(year: Current.year)

    assert_response :success
    assert_select "#qualifications-header", text: /Qualifications/
    assert_select "a[href='#{me_timesheet_dashboard_path(year: Current.year)}']", text: /Timesheet/
  end

  test "every row carries an on-duty bar and its eligibility, an open row adds the hatched estimate, and each section states the rule" do
    set_threshold Setting::SHIRT_SHORT_SLEEVE_HOURS_THRESHOLD, 0
    set_threshold Setting::SHOWER_ACCESS_EVENT_WEEK_THRESHOLD, 60
    set_threshold Setting::SC_TICKET_THRESHOLD, 38

    get me_timesheet_dashboard_qualifications_url(year: Current.year)

    assert_select "#qual-shower_access_event_week-title", text: /Sign up for 60 hr more/ do |row|
      assert_select "[role='progressbar']", 2
      assert_select "[role='progressbar'][aria-label$='on duty'][aria-valuenow='0'].bg-primary", 1
      assert_select "[role='progressbar'][aria-label$='with sign-ups, estimate'][aria-valuenow='0'].progress-projected", 1
      # Nothing on duty yet: no percentage fits inside an empty fill, so none is printed
      assert_select "[role='progressbar'] span", 0
      assert_match(/On Duty\s+0 of 60 hr/, row.text)
      assert_match(/With Sign-Ups\s+0 hr with 0 hr signed up, estimate/, row.text)
    end
    # Credits: the threshold at two places, and zero spelled in the unit it is counted in
    assert_select "#qual-staff_credential-title" do |row|
      assert_match(/On Duty\s+0 of 38\.00 credits/, row.text)
      assert_match(/With Sign-Ups\s+0 credits with 0 credits signed up, estimate/, row.text)
    end
    assert_select "#qual-t_shirt-title", text: /Earned/ do |row|
      assert_select "[role='progressbar']", 1
      assert_select "[role='progressbar'][aria-label$='on duty'].bg-success", 1
      # A full bar says it without a number (white on green fails contrast in dark mode)
      assert_select "[role='progressbar'] span", 0
      assert_no_match(/With Sign-Ups/, row.text)
      # Kept once earned: it names the hours the On Duty figure counts
      assert_match(/Eligibility: combined Pre-Event & Event Week hours only/, row.text)
    end
    assert_select "section[aria-label='Showers Qualification']", text: /Awards are based on time on duty\. Sign-ups are estimates until rangered\./
    # Not yet is no warning: the amber belongs to the callout alone.
    assert_select "[id^='qual-'] .icon-warning", 0
  end

  test "the on-duty percentage prints inside the bar only where it fits" do
    set_threshold Setting::SHOWER_ACCESS_EVENT_WEEK_THRESHOLD, 60
    set_threshold Setting::SHOWER_POG_THRESHOLD, 200
    # 12 hours on duty; with no event dates recorded, every hour is booked to the event period
    on_duty = Time.zone.local(Current.year, 6, 1, 8)
    Timesheet.create!(person: @person, position: positions(:ood_position), on_duty:, off_duty: on_duty + 12.hours,
                      additional_notes: "test shift")

    get me_timesheet_dashboard_qualifications_url(year: Current.year)

    assert_select "#qual-shower_access_event_week-title [role='progressbar'][aria-label$='on duty']", text: "20%"
    # 12 of 200 hr is 6%: the label would be cut off, so the figure above the bar says it alone
    assert_select "#qual-shower_pog-title [role='progressbar'] span", 0
  end

  test "the next step card comes first, holds the one sign-ups button, and the callout follows it" do
    set_threshold Setting::SHOWER_ACCESS_EVENT_WEEK_THRESHOLD, 60

    get me_timesheet_dashboard_qualifications_url(year: Current.year)

    assert_select "#qualifications-next-step", text: /Sign up for 60 hr more during Event Week/ do
      assert_select "a", 1
      assert_select "a.btn-primary[href=?]", me_available_sign_up_path, text: /View Available Sign-Ups/
    end
    assert_select "article#qualifications-important[class~='border-warning/30']",
                  text: /Important: Read Before Checking Your Progress/
  end

  test "with every goal earned the card says so, offers no sign-ups, and every section is earned" do
    TicketsAndProvisionsProgress::THRESHOLD_SETTINGS.each { |name| set_threshold name, 0 }

    get me_timesheet_dashboard_qualifications_url(year: Current.year)

    assert_select "#qualifications-next-step", text: /You have earned everything available this year/ do
      assert_select "a", 0
    end
    assert_select "section[aria-label$='Qualification'] .badge", text: "Earned", count: 4
  end

  test "after event week an Event Week row is closed and the next step moves to a row that can still be earned" do
    set_threshold Setting::SHOWER_ACCESS_EVENT_WEEK_THRESHOLD, 60
    set_threshold Setting::SHOWER_ACCESS_ENTIRE_EVENT_THRESHOLD, 130
    travel_to Time.zone.local(Current.year, 9, 20, 12) # past Labor Day, no event dates recorded

    get me_timesheet_dashboard_qualifications_url(year: Current.year)

    assert_select "#qual-shower_access_event_week-title", text: /Not earned this year/ do |row|
      # No sign-up can help a closed row, so its estimate bar is spent
      assert_select "[role='progressbar']", 1
      assert_select "[role='progressbar'][aria-label$='on duty'].bg-secondary", 1
      assert_no_match(/With Sign-Ups/, row.text)
      assert_match(/Eligibility/, row.text)
    end
    assert_select "#qual-shower_access_entire_event-title", text: /Sign up for 130 hr more/
    assert_select "#qualifications-next-step", text: /Sign up for 130 hr more to earn the Wet Spot Access for NEXT event \(Combined hours\)/ do
      assert_select "a.btn-primary", 1
    end
    assert_select "section[aria-label='Showers Qualification'] .badge", text: "Needs Sign-Ups"
  end

  test "after post-event nothing open can be earned, so the card offers no sign-ups and the section says not this year" do
    set_threshold Setting::SHOWER_ACCESS_EVENT_WEEK_THRESHOLD, 60
    set_threshold Setting::SHOWER_ACCESS_ENTIRE_EVENT_THRESHOLD, 130
    year = Current.year
    EventDate.create!(event_start: Time.zone.local(year, 8, 25), event_end: Time.zone.local(year, 9, 1),
                      pre_event_start: Time.zone.local(year, 8, 10), pre_event_slot_start: Time.zone.local(year, 8, 10),
                      pre_event_slot_end: Time.zone.local(year, 8, 25), post_event_end: Time.zone.local(year, 9, 10))
    travel_to Time.zone.local(year, 9, 20, 12)

    get me_timesheet_dashboard_qualifications_url(year:)

    assert_select "#qualifications-next-step", text: /Nothing still open can be earned this year/ do
      assert_select "a", 0
    end
    assert_select "#qualifications-next-step", text: /1 not this year/
    assert_select "#qual-shower_access_entire_event-title", text: /Not earned this year/
    assert_select "section[aria-label='Showers Qualification'] .badge", text: "Not This Year"
  end

  test "only sign-ups whose hours count go into the hours estimate" do
    set_threshold Setting::ALL_YOU_CAN_EAT_EVENT_PERIOD_THRESHOLD, 100
    year = Current.year
    EventDate.create!(event_start: Time.zone.local(year, 8, 25), event_end: Time.zone.local(year, 9, 1),
                      pre_event_start: Time.zone.local(year, 8, 10), pre_event_slot_start: Time.zone.local(year, 8, 10),
                      pre_event_slot_end: Time.zone.local(year, 8, 25), post_event_end: Time.zone.local(year, 9, 10))
    on_call = Position.create!(title: "Test On Call", active: true, type: Position::TYPE_FRONTLINE, count_hours: false)
    [positions(:ood_position), on_call].each do |position|
      begins = Time.zone.local(year, 8, 27, 9)
      slot = Slot.create!(position:, begins:, ends: begins + 8.hours, max: 10, active: true,
                          timezone: "America/Los_Angeles")
      PersonSlot.create!(person: @person, slot:)
    end

    get me_timesheet_dashboard_qualifications_url(year:)

    # 8 hours, not 16: the On Call shift's hours never count toward a provision
    assert_select "#qual-all_eats-title" do |row|
      assert_match(/With Sign-Ups\s+8 hr with 8 hr signed up, estimate/, row.text)
    end
    assert_select "#qual-all_eats-title", text: /Sign up for 92 hr more/
  end

  private

  def set_threshold(name, value)
    Setting.find_or_create_by(name:).update!(value: value.to_s)
  end
end
