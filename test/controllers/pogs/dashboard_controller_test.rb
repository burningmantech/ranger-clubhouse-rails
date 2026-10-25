# frozen_string_literal: true

require "test_helper"

class Pogs::DashboardControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role

  setup do
    Rails.cache.clear
    Current.reset

    @admin = person(:active_ranger)
    @pog_manager = person(:echelon_ranger)
    # The realistic wrong role: it owns Person › Pogs and the HQ pog flow.
    @event_manager = person(:auditor_ranger)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::POG_MANAGEMENT, "Pog Management")
    ensure_role(Role::EVENT_MANAGEMENT, "Event Management")
    grant_role(@admin, Role::ADMIN)
    grant_role(@pog_manager, Role::POG_MANAGEMENT)
    grant_role(@event_manager, Role::EVENT_MANAGEMENT)
  end

  teardown do
    Current.reset
    Rails.cache.clear
  end

  test "admin and pog management may view the page" do
    [@admin, @pog_manager].each do |viewer|
      sign_in_as(viewer)
      get pogs_dashboard_path
      assert_response :success, "#{viewer.callsign} should be allowed in"
    end
  end

  test "event management alone is turned away" do
    sign_in_as(@event_manager)
    get pogs_dashboard_path

    assert_redirected_to me_root_path
    assert_equal "Admin or Pog Management role required to view pog statistics.", flash[:error]
  end

  # A pog belongs to the year it was issued in, not the year its row was written.
  test "a year holds the pogs issued in it" do
    pog = PersonPog.create!(person: @event_manager, issued_by: @admin, pog: PersonPog::POG_MEAL,
                            issued_at: Time.local(2025, 8, 27, 12))
    pog.update_column(:created_at, Time.local(2026, 1, 5, 12))
    sign_in_as(@pog_manager)

    get pogs_dashboard_path(year: 2025)
    assert_response :success
    assert_select ".empty-state", count: 0
    # The copy names the year shown, not the current one.
    assert_match "issued in 2025, by day and type", css_select("main").sole.text.squish

    get pogs_dashboard_path(year: 2026)
    assert_select ".empty-state", text: "No pogs were issued in 2026."
  end

  # Pog Administration answers to the same gate, so every reader may follow
  # these, Pog Management alone included. The issued-status filter makes the
  # list each opens hold exactly the pogs the count beside the name counts.
  test "each top-ten name opens pog administration filtered to that person's issued pogs" do
    PersonPog.create!(person: @event_manager, issued_by: @admin, pog: PersonPog::POG_MEAL,
                      issued_at: Time.local(2025, 8, 27, 12))
    sign_in_as(@pog_manager)

    get pogs_dashboard_path(year: 2025)

    issued = PogFilterForm::STATUS_ISSUED
    assert_select "a[href=?]", pogs_administration_path(year: 2025, filter: { issued_by_id: @admin.id, status: issued }),
                  text: @admin.callsign
    assert_select "a[href=?]",
                  pogs_administration_path(year: 2025, filter: { person_callsign: @event_manager.callsign, status: issued }),
                  text: @event_manager.callsign
  end

  # Not an empty page -- the year holds a pog -- but nothing was issued, so the
  # by-day table would be headings over no rows.
  test "a year whose only pogs were cancelled says so by day" do
    PersonPog.create!(person: @event_manager, issued_by: @admin, pog: PersonPog::POG_MEAL,
                      status: PersonPog::STATUS_CANCELLED, issued_at: Time.local(2025, 8, 27, 12))
    sign_in_as(@pog_manager)

    get pogs_dashboard_path(year: 2025)

    assert_response :success
    assert_select ".empty-state", text: "No pogs were issued in 2025: every pog recorded was cancelled."
    assert_select ".empty-state", text: "None in 2025.", count: 2
  end
end
