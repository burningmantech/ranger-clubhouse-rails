# frozen_string_literal: true

require "test_helper"

# Ticketing > Maintenance: the launcher, the preview/commit dispatch, and the
# guard rails (roles, unknown slugs, required reasons, blank settings). The
# per-task business rules live in test/lib/ticketing_maintenance_test.rb.
#
# The tasks sweep whole tables and the shared fixtures belong to other suites,
# so every test starts from empty tables and builds exactly the rows it needs.
class Ticketing::MaintenanceControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include ActiveSupport::Testing::TimeHelpers

  YEAR = 2026

  setup do
    travel_to Time.zone.local(YEAR, 9, 10, 12, 0, 0)
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
    Timesheet.delete_all
    PersonSlot.delete_all

    sign_in_as(@admin)
  end

  teardown do
    Current.reset
    Rails.cache.clear
    travel_back
  end

  # --- who may look ----------------------------------------------------------

  test "the launcher renders for an admin with every task card" do
    get ticketing_maintenance_path

    assert_response :success
    assert_match "Before Ticketing Opens", response.body
    assert_match "After the Event", response.body
    TicketingMaintenance::TASKS.each do |task|
      assert_select "a[href=?]", ticketing_maintenance_preview_path(task.slug)
    end
    assert_select "a[href=?]", ticketing_unsubmit_provisions_path
  end

  test "the launcher renders with only the edit access documents role" do
    sign_in_as(@ticketing)

    get ticketing_maintenance_path

    assert_response :success
  end

  test "the launcher is refused without the admin or edit access documents role" do
    sign_in_as(@outsider)

    get ticketing_maintenance_path

    assert_redirected_to me_root_path
    assert_equal "Admin or Edit Access Documents role required to run ticketing maintenance.",
                 flash[:error]
  end

  test "an unknown task slug is not found" do
    get ticketing_maintenance_preview_path("mystery-task")

    assert_response :not_found
  end

  # --- preview then commit ---------------------------------------------------

  test "a preview lists the ledger and saves nothing" do
    ticket = banked_ticket

    get ticketing_maintenance_preview_path("unbank-tickets")

    assert_response :success
    assert_match "banked → qualified", response.body
    assert_match "Nothing has changed yet", response.body
    assert_select "form[action=?]", ticketing_maintenance_commit_path("unbank-tickets")
    assert_equal AccessDocument::BANKED, ticket.reload.status
    # The hero says what this page does, in one sentence. What the task does is
    # the task's own description, which runs longer and so is body copy.
    description = TicketingMaintenance.find("unbank-tickets").description
    assert_select "section.me-hero-panel", text: /#{Regexp.escape(description)}/, count: 0
    assert_select "p", text: description
  end

  test "an expire preview shows the email column for rows that carry one" do
    AccessDocument.create!(person: @admin, type: AccessDocument::SPT,
                           status: AccessDocument::BANKED,
                           delivery_method: AccessDocument::DELIVERY_NONE,
                           source_year: YEAR, expiry_date: Date.current - 1)

    get ticketing_maintenance_preview_path("expire-tickets")

    assert_response :success
    assert_select "th", text: "Email"
    assert_select "a[href=?]", "mailto:#{@admin.email}"
  end

  test "an empty preview offers no commit form" do
    get ticketing_maintenance_preview_path("unbank-tickets")

    assert_response :success
    assert_match "No matching records found", response.body
    # main: the navbar mega menu keeps its star form on every page
    assert_select "main form", count: 0
  end

  test "a commit runs the task and renders its ledger at 422" do
    ticket = banked_ticket

    post ticketing_maintenance_commit_path("unbank-tickets")

    assert_response :unprocessable_entity
    assert_select "[data-controller=scroll-to-top]"
    assert_match "This task has finished", response.body
    assert_match "banked → qualified", response.body
    assert_equal AccessDocument::QUALIFIED, ticket.reload.status
  end

  # --- bump expiration wants a reason ----------------------------------------

  test "bump expiration re-renders the preview when the reason is blank" do
    ticket = bumpable_ticket

    post ticketing_maintenance_commit_path("bump-expiration"), params: { reason: "  " }

    assert_response :unprocessable_entity
    assert_match "Enter a reason", response.body
    assert_equal Date.new(YEAR + 1, 9, 15), ticket.reload.expiry_date
  end

  test "bump expiration runs with a reason" do
    ticket = bumpable_ticket

    post ticketing_maintenance_commit_path("bump-expiration"), params: { reason: "vendor delay" }

    assert_response :unprocessable_entity
    assert_match "This task has finished", response.body
    assert_equal Date.new(YEAR + 2, 9, 15), ticket.reload.expiry_date
  end

  # --- blank settings block the grants ----------------------------------------

  test "a task missing its setting shows why and refuses to commit" do
    person(:alpha_ranger) # an alpha the task would otherwise cover

    get ticketing_maintenance_preview_path("grant-alpha-saps")

    assert_response :success
    assert_match "This Task Cannot Run Yet", response.body
    assert_match "TAS_DefaultAlphaWAPDate", response.body
    # main: the navbar mega menu keeps its star form on every page
    assert_select "main form", count: 0

    post ticketing_maintenance_commit_path("grant-alpha-saps")

    assert_response :unprocessable_entity
    assert_empty AccessDocument.where(type: AccessDocument::SAP)
  end

  private

  def banked_ticket
    AccessDocument.create!(person: @admin, type: AccessDocument::SPT,
                           status: AccessDocument::BANKED,
                           delivery_method: AccessDocument::DELIVERY_NONE,
                           source_year: YEAR, expiry_date: "#{YEAR + 1}-09-15")
  end

  def bumpable_ticket
    AccessDocument.create!(person: @admin, type: AccessDocument::SPT,
                           status: AccessDocument::QUALIFIED,
                           delivery_method: AccessDocument::DELIVERY_NONE,
                           source_year: YEAR, expiry_date: "#{YEAR + 1}-09-15")
  end
end
