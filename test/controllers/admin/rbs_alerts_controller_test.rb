# frozen_string_literal: true

require "test_helper"

class Admin::RbsAlertsControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper

  setup do
    Rails.cache.clear

    @admin = person(:auditor_ranger)
    @tech_ninja = person(:echelon_ranger)
    @outsider = person(:retired_ranger)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::TECH_NINJA, "Tech Ninja")

    grant_role(@admin, Role::ADMIN)
    grant_role(@tech_ninja, Role::ADMIN)
    grant_role(@tech_ninja, Role::TECH_NINJA)

    @alert = alert(:shift_change)

    # After the fixture rows, so their own audit entries do not stand in for
    # the one a test is looking for.
    ActionLog.delete_all
  end

  teardown do
    Rails.cache.clear
  end

  # ---------------------------------------------------------------- index

  test "admin sees every alert" do
    sign_in_as(@admin)

    get admin_rbs_alerts_path

    assert_response :success
    assert_select "h1", text: /RBS Alerts/
    Alert.pluck(:title).each { |title| assert_select "td", text: /#{Regexp.escape(title)}/ }
  end

  test "alerts are split by the group Rangers see them in" do
    sign_in_as(@admin)

    get admin_rbs_alerts_path

    assert_response :success
    assert_select "[role=heading]", text: /On Playa Alerts/
    assert_select "[role=heading]", text: /Pre & Post Event Alerts/
  end

  test "the channels an alert may use are shown" do
    sign_in_as(@admin)

    get admin_rbs_alerts_path

    assert_response :success
    # Emergency Broadcast cannot be opted out of, On Shift is SMS only, and
    # Ranger Contact is email only -- all three decided by id, not by the form.
    assert_select "td", text: /Required/
    assert_select "td", text: /SMS only/
    assert_select "td", text: /Email only/
  end

  test "a person with neither role is turned away" do
    sign_in_as(@outsider)

    get admin_rbs_alerts_path

    assert_redirected_to me_root_path
  end

  # ----------------------------------------------------------- affordances

  test "tech ninja is offered an edit link for every alert" do
    sign_in_as(@tech_ninja)

    get admin_rbs_alerts_path

    assert_response :success
    Alert.pluck(:id).each do |id|
      assert_select "a[href=?]", edit_admin_rbs_alert_path(id)
    end
  end

  test "an admin who is not on the tech team reads the list but is offered no writes" do
    sign_in_as(@admin)

    get admin_rbs_alerts_path

    assert_response :success
    assert_select "a[href=?]", edit_admin_rbs_alert_path(@alert), count: 0
    assert_select "body", text: /Contact the Tech Team to change an alert/
  end

  # --------------------------------------------------------------- edit

  test "tech ninja opens the edit form" do
    sign_in_as(@tech_ninja)

    get edit_admin_rbs_alert_path(@alert)

    assert_response :success
    assert_select "input[name=?]", "alert[title]"
    assert_select "textarea[name=?]", "alert[description]"
    assert_select "input[type=checkbox][name=?]", "alert[on_playa]"
  end

  test "the edit form names the channels the alert may use" do
    sign_in_as(@tech_ninja)

    get edit_admin_rbs_alert_path(alert(:on_shift))

    assert_response :success
    assert_select "body", text: /Rangers are offered an SMS checkbox only/
  end

  test "an admin who is not on the tech team cannot open the edit form" do
    sign_in_as(@admin)

    get edit_admin_rbs_alert_path(@alert)

    assert_redirected_to admin_rbs_alerts_path
    assert_equal "You are not authorized to change alerts.", flash[:error]
  end

  # --------------------------------------------------------------- update

  test "tech ninja rewrites an alert" do
    sign_in_as(@tech_ninja)

    patch admin_rbs_alert_path(@alert),
          params: { alert: { title: "Shift Changes", description: "A shift moved.", on_playa: "1" } }

    assert_redirected_to admin_rbs_alerts_path
    @alert.reload
    assert_equal "Shift Changes", @alert.title
    assert_equal "A shift moved.", @alert.description
    assert @alert.on_playa
  end

  test "an alert can be moved back out of the on playa group" do
    sign_in_as(@tech_ninja)
    @alert.update!(on_playa: true)

    patch admin_rbs_alert_path(@alert),
          params: { alert: { title: "Shift Changes", description: "A shift moved.", on_playa: "0" } }

    assert_not @alert.reload.on_playa
  end

  test "surrounding whitespace is trimmed off both fields" do
    sign_in_as(@tech_ninja)

    patch admin_rbs_alert_path(@alert),
          params: { alert: { title: "  Shift Changes  ",
                             description: "A shift moved.\r\n", on_playa: "0" } }

    @alert.reload
    assert_equal "Shift Changes", @alert.title
    assert_equal "A shift moved.", @alert.description
  end

  test "rewriting an alert is recorded in the audit log" do
    sign_in_as(@tech_ninja)

    patch admin_rbs_alert_path(@alert),
          params: { alert: { title: "Shift Changes", description: "A shift moved.", on_playa: "0" } }

    assert ActionLog.where(event: "alert-update").exists?
  end

  test "a blank title re-renders the form with the reason" do
    sign_in_as(@tech_ninja)

    patch admin_rbs_alert_path(@alert),
          params: { alert: { title: "", description: "A shift moved.", on_playa: "0" } }

    assert_response :unprocessable_entity
    assert_select "body", text: /Enter a title for the alert/
    assert_equal "Shift Change Notifications", @alert.reload.title
  end

  test "a blank description re-renders the form with the reason" do
    sign_in_as(@tech_ninja)

    patch admin_rbs_alert_path(@alert),
          params: { alert: { title: "Shift Changes", description: " ", on_playa: "0" } }

    assert_response :unprocessable_entity
    assert_select "body", text: /Describe what the alert tells a Ranger/
    assert_equal "Shift Change Notifications", @alert.reload.title
  end

  test "a title longer than the column re-renders the form instead of truncating" do
    sign_in_as(@tech_ninja)

    patch admin_rbs_alert_path(@alert),
          params: { alert: { title: "T" * 256, description: "A shift moved.", on_playa: "0" } }

    assert_response :unprocessable_entity
    assert_select "body", text: /The alert title is too long. Use 255 characters or fewer/
    assert_equal "Shift Change Notifications", @alert.reload.title
  end

  test "an admin who is not on the tech team cannot rewrite an alert" do
    sign_in_as(@admin)

    patch admin_rbs_alert_path(@alert),
          params: { alert: { title: "Something else", description: "Nope.", on_playa: "0" } }

    assert_redirected_to admin_rbs_alerts_path
    assert_equal "You are not authorized to change alerts.", flash[:error]
    assert_equal "Shift Change Notifications", @alert.reload.title
  end

  # ------------------------------------------------------- edit only

  test "alerts cannot be created or deleted" do
    sign_in_as(@tech_ninja)

    assert_no_difference "Alert.count" do
      post admin_rbs_alerts_path, params: { alert: { title: "New", description: "New." } }
      assert_response :not_found

      delete admin_rbs_alert_path(@alert)
      assert_response :not_found
    end
  end
end
