# frozen_string_literal: true

require "test_helper"

class Hq::IndexControllerTest < ActionDispatch::IntegrationTest
  include ActiveSupport::Testing::TimeHelpers
  include AuthenticationTestHelper
  include EmailSuppressionTestHelper
  include TimesheetAdminTestHelper

  setup do
    Rails.cache.clear
    Current.reset

    @viewer = person(:active_ranger)
    @subject = person(:ranger_with_custom_gender)

    ensure_role(Role::SHIFT_MANAGEMENT, "Shift Management")
    grant_role(@viewer, Role::SHIFT_MANAGEMENT)

    sign_in_as(@viewer)
  end

  teardown do
    travel_back
    Current.reset
    Rails.cache.clear
  end

  test "redirects away when the HQ Window Interface setting is off" do
    Setting.find_or_create_by(name: Setting::HQ_WINDOW_INTERFACE_ENABLED).update!(value: "false")

    get hq_path(@subject)

    assert_redirected_to person_path(@subject)
    assert_equal "The HQ Window Interface is not currently available.", flash[:error]
  end

  test "requires the admin or shift management permission" do
    sign_in_as(@subject)

    get hq_path(@viewer)

    assert_redirected_to me_root_path
  end

  test "a person already on site is sent to shift manage" do
    @subject.update_columns(on_site: true)

    get hq_path(@subject)

    assert_redirected_to hq_shift_manage_path(@subject)
  end

  test "a person not on site is sent to on-site registration" do
    @subject.update_columns(on_site: false)

    get hq_path(@subject)

    assert_redirected_to hq_site_registration_path(@subject)
  end

  test "an unknown person id bounces back to the dashboard" do
    get hq_path(person_id: 999_999)

    assert_redirected_to me_root_path
    assert_equal "Person not found", flash[:error]
  end

  # =========================================================================
  # The shell's email banner (EmailSuppression), shared with the person page
  # =========================================================================

  test "the shell's email banner says the address bounced, and when, without the address" do
    travel_to(Time.zone.local(2026, 10, 9, 14, 30, 0)) { suppress_email(@subject.email) }

    open_shell

    assert_select "#email-suppression-banner",
                  text: /Email to this account's address bounced on\s+Fri Oct 9, 2026 @ 14:30\./
    assert_not_includes css_select("#email-suppression-banner").to_s, @subject.email
  end

  test "the shell's email banner says the address reported a Clubhouse email as spam" do
    suppress_email(@subject.email, reason: EmailSuppression::COMPLAINT)

    open_shell

    assert_select "#email-suppression-banner", text: /Email to this account's address was reported as spam on/
  end

  # Shift Management opens the window; only Admin or Tech Ninja may clear.
  test "the shell's email banner offers the window worker no clear button" do
    suppress_email(@subject.email)

    open_shell

    assert_select "#email-suppression-banner"
    assert_select "a[href='#{person_email_suppression_clear_path(@subject)}']", count: 0
  end

  test "an admin in the window is offered the clear button" do
    ensure_role(Role::ADMIN, "Admin")
    grant_role(@viewer, Role::ADMIN)
    suppress_email(@subject.email)

    open_shell

    assert_select "#email-suppression-banner a[href='#{person_email_suppression_clear_path(@subject)}']" \
                  "[data-turbo-method='post']", text: "Clear Bounce Report"
  end

  test "no email banner shows in the shell without a row, nor for is_bouncing alone" do
    @subject.update_columns(is_bouncing: true)

    open_shell

    assert_select "#email-suppression-banner", count: 0
  end

  private

  # An HQ page that draws the shell: a person not on site lands on On-Site Registration.
  def open_shell
    # PersonEventInfo's training lookup falls back to Position.find(Position::TRAINING),
    # which the fixtures do not pin.
    Position.find_or_create_by!(id: Position::TRAINING) do |position|
      position.title = "In-Person Training"
      position.type = Position::TYPE_TRAINING
      position.active = true
    end
    @subject.update_columns(on_site: false)

    get hq_site_registration_path(@subject)
    assert_response :success
  end
end
