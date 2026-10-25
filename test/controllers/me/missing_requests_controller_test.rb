# frozen_string_literal: true

require "test_helper"

class Me::MissingRequestsControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper

  setup do
    @person = person(:active_ranger)
    sign_in_as(@person)

    # Enable timesheet corrections for testing
    Setting.find_or_create_by(name: Setting::TIMESHEET_CORRECTION_ENABLE).update!(value: "true")
  end

  teardown do
    # Disable after tests
    Setting.find_by(name: Setting::TIMESHEET_CORRECTION_ENABLE)&.update!(value: "false")
  end

  # Index tests

  test "should get index" do
    get me_missing_requests_url
    assert_response :success
  end

  test "index requires authentication" do
    sign_out

    get me_missing_requests_url
    assert_redirected_to root_path
  end

  test "index displays missing requests page" do
    get me_missing_requests_url
    assert_response :success

    assert_match /missing|request/i, response.body
  end

  test "redirects when corrections not enabled" do
    Setting.find_by(name: Setting::TIMESHEET_CORRECTION_ENABLE)&.update!(value: "false")

    get me_missing_requests_url
    assert_redirected_to me_timesheet_dashboard_path
    assert_equal "Timesheet corrections are not enabled.", flash[:error]
  end
end
