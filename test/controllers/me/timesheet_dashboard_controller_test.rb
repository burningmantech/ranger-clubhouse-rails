# frozen_string_literal: true

require "test_helper"

class Me::TimesheetDashboardControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper

  setup do
    @person = person(:active_ranger)
    sign_in_as(@person)
  end

  test "should get index" do
    get me_timesheet_dashboard_url
    assert_response :success
  end

  test "index displays timesheet dashboard" do
    get me_timesheet_dashboard_url
    assert_response :success

    # Dashboard should show timesheet-related content
    assert_match /timesheet|shift|hour/i, response.body
  end

  test "index requires authentication" do
    sign_out

    get me_timesheet_dashboard_url
    assert_redirected_to root_path
  end

  test "index can accept year parameter" do
    get me_timesheet_dashboard_url(year: 2023)
    assert_response :success
  end

  test "echelon user can view timesheet dashboard" do
    sign_out
    echelon_person = person(:echelon_ranger)
    sign_in_as(echelon_person)

    get me_timesheet_dashboard_url
    assert_response :success
  end

  test "dashboard shows link to work history" do
    get me_timesheet_dashboard_url
    assert_response :success

    assert_select "a[href=?]", me_work_history_path, text: /Work History/
  end

  test "dashboard shows link to event summary" do
    get me_timesheet_dashboard_url
    assert_response :success

    assert_match /event.summary/i, response.body
  end
end
