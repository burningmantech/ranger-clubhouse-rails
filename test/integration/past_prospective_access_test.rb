# frozen_string_literal: true

require "test_helper"

# A past prospective reaches the dashboard and their own profile, and nothing
# else (ApplicationController#confine_past_prospective).
class PastProspectiveAccessTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper

  setup do
    Rails.cache.clear
    Current.reset
    sign_in_as(person(:past_prospective_ranger))
  end

  test "the dashboard and every profile page open" do
    [me_root_path, me_profile_path, me_edit_profile_section_path("identity-info"),
     me_profile_languages_path, me_profile_edit_password_path, new_me_profile_photo_path,
     edit_me_alerts_path].each do |path|
      get path

      assert_response :success, path
    end
  end

  test "every other page sends them back to the dashboard" do
    [me_schedule_path, me_available_sign_up_path, me_tickets_path, me_agreements_path,
     me_announcements_path, me_messages_path, me_operational_summary_path,
     new_bug_report_path, admin_bug_reports_path].each do |path|
      get path

      assert_redirected_to me_root_path, path
      assert_equal "You are not authorized to view the page.", flash[:error]
    end
  end

  test "the menu offers only the dashboard and the profile" do
    get me_root_path

    assert_select "a[href=?]", me_profile_path
    [me_schedule_path, me_tickets_path, me_agreements_path, me_announcements_path,
     new_bug_report_path].each do |path|
      assert_select "a[href=?]", path, count: 0
    end
  end

  test "they can still sign out" do
    delete logout_path

    assert_redirected_to root_path
  end
end
