# frozen_string_literal: true

require "test_helper"

class Hq::TicketsProvisionsControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
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
    Current.reset
    Rails.cache.clear
  end

  test "requires the admin or shift management permission" do
    sign_in_as(@subject)

    get hq_tickets_provisions_path(@viewer)

    assert_redirected_to me_root_path
  end

  test "redirects away when the HQ Window Interface setting is off" do
    Setting.find_or_create_by(name: Setting::HQ_WINDOW_INTERFACE_ENABLED).update!(value: "false")

    get hq_tickets_provisions_path(@subject)

    assert_redirected_to person_path(@subject)
  end

  test "renders the modal shell with a lazy progress frame" do
    get hq_tickets_provisions_path(@subject)

    assert_response :success
    assert_select "dialog#hq-tickets-provisions-dialog"
    assert_select "turbo-frame#hq-tickets-provisions-progress[loading=?]", "lazy"
    assert_select "turbo-frame#hq-tickets-provisions-progress[src=?]",
                  hq_tickets_provisions_path(@subject, progress: 1)
  end

  test "renders the four progress tables and hides superseded rows" do
    # Ticket/meal/shirt thresholds default to zero, so those items read as
    # earned — which also exercises the row-suppression rules (SPT hidden when
    # the Staff Credential is earned; Event Week Eat Pass hidden when the All
    # Eat pass is earned).
    get hq_tickets_provisions_path(@subject, progress: 1)

    assert_response :success
    ["Tickets", "Meal Passes", "Ranger Clothing", "Wet Spot (Burning Man Org Showers)"].each do |title|
      assert_match title, response.body
    end
    assert_match "Staff Credential", response.body
    assert_match "&mdash; earned", response.body
    assert_no_match "Special Price Ticket", response.body
    assert_no_match "Event Week Eat Pass", response.body
    assert_match "All Eat Meal Pass", response.body
    assert_match "Wet Spot Pog for this event", response.body
  end

  test "unearned items show the sign-up and on-duty coaching lines" do
    Setting.find_or_create_by(name: Setting::SC_TICKET_THRESHOLD).update!(value: "30")
    Setting.find_or_create_by(name: Setting::SP_TICKET_THRESHOLD).update!(value: "15")

    get hq_tickets_provisions_path(@subject, progress: 1)

    assert_response :success
    assert_match "Special Price Ticket", response.body
    assert_match "more in scheduled sign-ups", response.body
    assert_match "more on duty", response.body
  end
end
