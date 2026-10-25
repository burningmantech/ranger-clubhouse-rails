# frozen_string_literal: true

require "test_helper"

# Ticketing > Statistics: who may read the dashboard and what it draws.
#
# The counting rules themselves live in TicketingStatisticsTest; this suite
# covers the gate and the rendering, including the empty table that used to be
# the page's only way to divide by zero.
class Ticketing::StatisticsControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include ActiveSupport::Testing::TimeHelpers
  include TicketingTestHelper

  YEAR = 2026

  setup do
    travel_to Time.zone.local(YEAR, 4, 8, 12, 0, 0)
    Rails.cache.clear
    Current.reset

    @admin = person(:active_ranger)
    @ticketing = person(:echelon_ranger)
    @outsider = person(:inactive_ranger)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::EDIT_ACCESS_DOCS, "Edit Access Documents")
    grant_role(@admin, Role::ADMIN)
    grant_role(@ticketing, Role::EDIT_ACCESS_DOCS)

    AccessDocument.delete_all
    Provision.delete_all

    sign_in_as(@admin)
  end

  teardown do
    Current.reset
    Rails.cache.clear
    travel_back
  end

  # --- who may look ---------------------------------------------------------

  test "the dashboard renders for an admin" do
    get ticketing_statistics_path

    assert_response :success
    assert_select "h1", text: /Ticketing Statistics/
  end

  test "the dashboard renders with only the edit access documents role" do
    sign_in_as(@ticketing)

    get ticketing_statistics_path

    assert_response :success
  end

  test "the dashboard is refused without the admin or edit access documents role" do
    sign_in_as(@outsider)

    get ticketing_statistics_path

    assert_redirected_to me_root_path
    assert_equal "Admin or Edit Access Documents role required to view ticketing statistics.", flash[:error]
  end

  # --- what it draws --------------------------------------------------------

  test "every type gets a card, whether or not it is holding anything" do
    get ticketing_statistics_path

    assert_response :success
    TicketingStatistics::TYPES.each do |spec|
      assert_select "h3", text: spec[:label]
    end
  end

  test "an empty table renders without a meter segment" do
    get ticketing_statistics_path

    assert_response :success
    assert_select ".stat-meter", count: TicketingStatistics::TYPES.size
    assert_select ".stat-meter-segment", count: 0
  end

  test "a type holding documents draws one meter segment per occupied status" do
    holder = person(:retired_ranger)
    document(holder, type: AccessDocument::SPT, status: AccessDocument::CLAIMED)
    document(holder, type: AccessDocument::SPT, status: AccessDocument::BANKED)

    get ticketing_statistics_path

    assert_response :success
    assert_select ".stat-meter-segment", count: 2, message: "qualified and submitted are empty"
  end

  # The meter is decorative; the counts have to survive without it.
  test "the counts are printed as text beside the meter" do
    document(person(:retired_ranger), type: AccessDocument::GIFT, status: AccessDocument::CLAIMED)

    get ticketing_statistics_path

    assert_response :success
    assert_select ".stat-meter[aria-hidden=?]", "true"
    assert_match "Gift Tickets", response.body
    assert_select "h3", text: "Gift Tickets"
  end
end
