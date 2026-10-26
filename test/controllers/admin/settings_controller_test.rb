# frozen_string_literal: true

require "test_helper"

class Admin::SettingsControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper

  setup do
    admin = person(:auditor_ranger)
    ensure_role(Role::ADMIN, "Admin")
    grant_role(admin, Role::ADMIN)
    sign_in_as(admin)
  end

  # A setting nobody has saved yet is a new record, and its edit form used to
  # POST to a route that does not exist, so the value was never stored.
  test "saving a setting with no row yet stores it" do
    name = Setting::BROADCAST_MAIL_TEST_ADDRESS
    assert_not Setting.exists?(name:)

    get edit_admin_setting_path(name, filter: "mailtest")
    assert_select "form[action=?] input[name=_method][value=patch]", admin_setting_path(name)

    patch admin_setting_path(name), params: { filter: "mailtest", setting: { value: "test+?@example.com" } }

    assert_redirected_to admin_settings_path(filter: "mailtest")
    assert_equal "test+?@example.com", Setting.find_by!(name:).value
  end

  test "TwilioMessagingServiceId is a credential, hidden and refused without Tech Ninja as the other Twilio settings are" do
    name = Setting::TWILIO_MESSAGING_SERVICE_ID
    Setting.find_or_initialize_by(name:).update!(value: "MG0123456789abcdef0123456789abcdef")

    get admin_settings_path(filter: "twilio")

    assert_select "tbody tr", 4
    assert_select "tbody tr", text: /#{name}.*Hidden.*No access/m
    assert_not_includes response.body, "MG0123456789abcdef0123456789abcdef"

    get edit_admin_setting_path(name)

    assert_response :redirect
    assert_equal admin_settings_path, URI(response.location).path
  end
end
