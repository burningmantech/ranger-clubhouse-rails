# frozen_string_literal: true

require "test_helper"

class Communication::RbsControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include RbsTestHelper
  include SesTestHelper

  setup do
    Rails.cache.clear
    Current.reset
    ensure_rbs_roles

    @admin = person(:active_ranger)
    @megaphone = person(:echelon_ranger)
    @team_lead = person(:retired_ranger)
    @outsider = person(:inactive_ranger)

    grant_role(@admin, Role::ADMIN)
    grant_role(@megaphone, Role::MEGAPHONE)
    grant_role(@team_lead, Role::MEGAPHONE_TEAM_ONPLAYA)
    enable_on_playa_roles

    sign_in_as(@admin)
  end

  teardown do
    Current.reset
    Rails.cache.clear
  end

  # ==========================================================================
  # Access
  # ==========================================================================

  test "denies access without a broadcasting role" do
    sign_in_as(@outsider)

    get communication_rbs_root_path

    assert_redirected_to me_root_path
    assert_equal "Admin, a Megaphone role, or Tech Ninja is required to open this page.", flash[:error]
  end

  test "a Megaphone role opens the launchpad" do
    sign_in_as(@megaphone)

    get communication_rbs_root_path

    assert_response :success
  end

  # ==========================================================================
  # What each permission is offered
  # ==========================================================================

  test "an admin is offered every kind of broadcast" do
    get communication_rbs_root_path

    assert_response :success
    Rbs::PAGE_TYPES.each do |type|
      assert_select "a[href=?]", communication_rbs_new_broadcast_path(type)
    end
  end

  test "a team permission is not offered the emergency or the general broadcast" do
    sign_in_as(@team_lead)

    get communication_rbs_root_path

    assert_response :success
    assert_select "a[href=?]", communication_rbs_new_broadcast_path(Broadcast::TYPE_POSITION)
    assert_select "a[href=?]", communication_rbs_new_broadcast_path(Broadcast::TYPE_EMERGENCY), false
    assert_select "a[href=?]", communication_rbs_new_broadcast_path(Broadcast::TYPE_GENERAL), false
  end

  test "a Megaphone role without the emergency permission is not offered it" do
    sign_in_as(@megaphone)

    get communication_rbs_root_path

    assert_select "a[href=?]", communication_rbs_new_broadcast_path(Broadcast::TYPE_GENERAL)
    assert_select "a[href=?]", communication_rbs_new_broadcast_path(Broadcast::TYPE_EMERGENCY), false
  end

  # ==========================================================================
  # The records
  # ==========================================================================

  test "an admin is shown the records" do
    get communication_rbs_root_path

    assert_select "a[href=?]", communication_rbs_history_path
    assert_select "a[href=?]", communication_rbs_messages_path
    assert_select "a[href=?]", communication_rbs_phone_numbers_path
  end

  test "a Megaphone role alone is not shown the records" do
    sign_in_as(@megaphone)

    get communication_rbs_root_path

    assert_select "a[href=?]", communication_rbs_history_path, false
  end

  # The Tech Team reads the records, and this page is the only way in to them.
  test "a Tech Ninja is admitted to read the records but is offered nothing to send" do
    tech = person(:prospective_ranger)
    grant_role(tech, Role::TECH_NINJA)
    sign_in_as(tech)

    get communication_rbs_root_path

    assert_response :success
    assert_select "a[href=?]", communication_rbs_history_path
    Rbs::PAGE_TYPES.each do |type|
      assert_select "a[href=?]", communication_rbs_new_broadcast_path(type), false
    end
  end

  test "someone with no broadcasting role at all is refused" do
    sign_in_as(@outsider)

    get communication_rbs_root_path

    assert_redirected_to me_root_path
  end

  test "the launchpad still shows while a test address that cannot be used is stored" do
    sandbox_off(Setting::BROADCAST_MAIL_SANDBOX)
    set_test_address("test@example.com")

    get communication_rbs_root_path

    assert_response :success
    assert_includes response.body, "Text messages and Clubhouse messages are recorded but not delivered."
    assert_not_includes response.body, "Emails Go to the Test Address"
  end

  test "the launchpad says where emails go while a test address is set" do
    sandbox_off(Setting::BROADCAST_MAIL_SANDBOX)
    set_test_address("test+?@example.com")

    get communication_rbs_root_path

    assert_includes response.body, "<strong>test+?@example.com</strong>"
    assert_not_includes response.body, "goes out for real",
                        "texts and Clubhouse messages are still sandboxed, so nothing goes out for real"
  end
end
