# frozen_string_literal: true

require "test_helper"

# Ticketing > Un-Submit Provisions: the recommendation table, its CSV export,
# and the checked-people commit. The report's selection rules live in
# test/lib/reports/unsubmit_provisions_report_test.rb.
#
# The report reads whole tables and the shared fixtures belong to other suites,
# so every test starts from empty tables and builds exactly the rows it needs.
class Ticketing::UnsubmitProvisionsControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include ActiveSupport::Testing::TimeHelpers

  YEAR = 2026

  setup do
    travel_to Time.zone.local(YEAR, 9, 10, 12, 0, 0)
    Rails.cache.clear
    Current.reset

    @admin = person(:active_ranger)
    @outsider = person(:inactive_ranger)
    @no_show = person(:ranger_with_custom_gender)

    ensure_role(Role::ADMIN, "Admin")
    grant_role(@admin, Role::ADMIN)

    AccessDocument.delete_all
    Provision.delete_all
    Timesheet.delete_all
    PersonSlot.delete_all
    Bmid.delete_all

    sign_in_as(@admin)
  end

  teardown do
    Current.reset
    Rails.cache.clear
    travel_back
  end

  test "the page lists no-shows with their provisions and context badges" do
    provision = claimed_provision(@no_show)

    get ticketing_unsubmit_provisions_path

    assert_response :success
    assert_select "a[href=?]", person_path(@no_show), text: @no_show.callsign
    assert_match "RP-#{provision.id}", response.body
    assert_select "input[name='person_ids[]'][value=?]", @no_show.id.to_s
  end

  test "the page is refused without the admin or edit access documents role" do
    sign_in_as(@outsider)

    get ticketing_unsubmit_provisions_path

    assert_redirected_to me_root_path
    assert_equal "Admin or Edit Access Documents role required to run ticketing maintenance.",
                 flash[:error]
  end

  test "an empty report says so and offers no form" do
    get ticketing_unsubmit_provisions_path

    assert_response :success
    assert_match "There is nothing to un-submit", response.body
    # main: the navbar mega menu keeps its star form on every page
    assert_select "main form", count: 0
  end

  test "the csv export returns the rows under the expected filename" do
    provision = claimed_provision(@no_show)

    get ticketing_unsubmit_provisions_path(format: :csv)

    assert_response :success
    assert_equal "text/csv", response.media_type
    assert_match %(filename="#{YEAR}-unsubmit-provisions.csv"), response.headers["Content-Disposition"]
    lines = response.body.split("\n")
    assert_equal "Callsign,Status,Ticket,SAP?,BMID Printed?,Sign-Ups?,Provisions", lines.first
    assert_equal [@no_show.callsign, @no_show.status, "", "N", "N", "N",
                  "RP-#{provision.id} Wet Spot Access claimed"].join(","),
                 lines.second
  end

  test "the commit returns the checked people's provisions to available at 422" do
    provision = claimed_provision(@no_show)
    unpicked = claimed_provision(@admin)

    post ticketing_unsubmit_provisions_commit_path, params: { person_ids: [@no_show.id] }

    assert_response :unprocessable_entity
    assert_select "[data-controller=scroll-to-top]"
    assert_match "claimed → available", response.body
    assert_equal Provision::AVAILABLE, provision.reload.status
    assert_equal Provision::CLAIMED, unpicked.reload.status
  end

  test "the commit with no one checked bounces back with an alert" do
    claimed_provision(@no_show)

    post ticketing_unsubmit_provisions_commit_path

    assert_redirected_to ticketing_unsubmit_provisions_path
    assert_equal "Select at least one person to un-submit.", flash[:alert]
  end

  # ActiveRecord reads "#{id}x" as the id, which returned that person's
  # provisions to available.
  test "the commit with person ids that are not ids un-submits nothing" do
    provision = claimed_provision(@no_show)

    post ticketing_unsubmit_provisions_commit_path, params: { person_ids: ["", "abc", "#{@no_show.id}x"] }

    assert_redirected_to ticketing_unsubmit_provisions_path
    assert_equal "Select at least one person to un-submit.", flash[:alert]
    assert_equal Provision::CLAIMED, provision.reload.status
  end

  private

  def claimed_provision(holder)
    Provision.create!(person: holder, type: Provision::WET_SPOT, status: Provision::CLAIMED,
                      is_allocated: false, source_year: YEAR, expires_on: "#{YEAR}-09-15")
  end
end
