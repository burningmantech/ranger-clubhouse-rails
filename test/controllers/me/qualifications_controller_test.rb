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

  test "an open row carries a progress bar with the projected total behind it, and an earned row folds" do
    set_threshold Setting::SHIRT_SHORT_SLEEVE_HOURS_THRESHOLD, 0
    set_threshold Setting::SHOWER_ACCESS_EVENT_WEEK_THRESHOLD, 60

    get me_timesheet_dashboard_qualifications_url(year: Current.year)

    assert_select "#qual-shower_access_event_week-title", text: /Sign up for 60 hr more/ do
      assert_select "[role='progressbar'][aria-valuenow]", 1
      assert_select "[aria-hidden='true'][style^='width:']", 1
    end
    assert_select "#qual-t_shirt-title", text: /Earned/ do |row|
      assert_select "[role='progressbar']", 0
      assert_no_match(/Eligibility/, row.text)
    end
    # Not yet is no warning: the amber belongs to the callout alone.
    assert_select "[id^='qual-'] .icon-warning", 0
  end

  test "the next step card comes first, holds the one sign-ups button, and the callout follows it" do
    set_threshold Setting::SHOWER_ACCESS_EVENT_WEEK_THRESHOLD, 60

    get me_timesheet_dashboard_qualifications_url(year: Current.year)

    assert_select "#qualifications-next-step", text: /Sign up for 60 hr more during Event Week/ do
      assert_select "a", 1
      assert_select "a.btn-primary[href=?]", me_available_sign_up_path, text: /View Available Sign-Ups/
    end
    assert_select "#qualifications-next-step + div", text: /Important: Read before checking your progress/
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
      assert_select "[role='progressbar']", 0
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

  private

  def set_threshold(name, value)
    Setting.find_or_create_by(name:).update!(value: value.to_s)
  end
end
