# frozen_string_literal: true

require "test_helper"

# Ticketing > Expiring Tickets: what counts as expiring, the already-expired
# flag, the three filters, and the CSV export.
#
# The action reads the whole access_document table and the shared fixtures
# belong to other suites, so every test starts from an empty table and builds
# exactly the documents it needs.
class Ticketing::ExpiringControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role

  include ActiveSupport::Testing::TimeHelpers

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

    sign_in_as(@admin)
  end

  teardown do
    Current.reset
    Rails.cache.clear
    travel_back
  end

  # --- who may look --------------------------------------------------------

  test "the report renders for an admin" do
    ticket_for(@admin)

    get ticketing_expiring_path

    assert_response :success
    assert_equal [@admin.callsign], rendered_callsigns
    assert_select "a[href=?]", person_tickets_provisions_path(@admin), text: @admin.callsign
    assert_match "Showing 1 of 1 expiring ticket", response.body
    # The ticket is good through the end of its expiry year, so the column
    # carries the year alone rather than a day and month that never vary.
    assert_equal [YEAR.to_s], rendered_expiry_years
  end

  test "the report renders with only the edit access documents role" do
    sign_in_as(@ticketing)
    ticket_for(@ticketing)

    get ticketing_expiring_path

    assert_response :success
    assert_equal [@ticketing.callsign], rendered_callsigns
  end

  test "the report is refused without the admin or edit access documents role" do
    sign_in_as(@outsider)

    get ticketing_expiring_path

    assert_redirected_to me_root_path
    assert_equal "Admin or Edit Access Documents role required to view ticketing reports.", flash[:error]
  end

  # --- what counts as expiring ---------------------------------------------

  test "qualified and banked regular tickets expiring this year are listed" do
    qualified = ticket_for(@admin)
    banked = ticket_for(@ticketing, status: AccessDocument::BANKED,
                                    type: AccessDocument::STAFF_CREDENTIAL)

    # Same types, further along the pipeline.
    (AccessDocument::CURRENT_STATUSES - ExpiringTicketsReport::STATUSES).each do |status|
      ticket_for(@outsider, status:)
    end
    # Qualified, but not a regular ticket.
    ticket_for(@outsider, type: AccessDocument::GIFT)
    ticket_for(@outsider, type: AccessDocument::SAP)

    get ticketing_expiring_path

    assert_response :success
    assert_equal [qualified.person.callsign, banked.person.callsign].sort, rendered_callsigns.sort
    assert_match "Showing 2 of 2 expiring tickets", response.body
  end

  test "a ticket expiring in a later year is not listed" do
    ticket_for(@admin, expiry_date: "#{YEAR + 1}-09-15")

    get ticketing_expiring_path

    assert_response :success
    assert_empty rendered_callsigns
  end

  test "a ticket with no expiry date is not listed" do
    ticket_for(@admin, expiry_date: nil)

    get ticketing_expiring_path

    assert_response :success
    assert_empty rendered_callsigns
  end

  test "rows are sorted by callsign regardless of case" do
    ticket_for(@ticketing)
    ticket_for(@admin)

    get ticketing_expiring_path

    assert_response :success
    expected = [@admin, @ticketing].map(&:callsign).sort_by(&:downcase)
    assert_equal expected, rendered_callsigns
  end

  # --- the already-expired flag --------------------------------------------

  test "a ticket that lapsed in an earlier year is flagged" do
    ticket_for(@admin, expiry_date: "#{YEAR - 1}-09-15")

    get ticketing_expiring_path

    assert_response :success
    # The header carries an "Already expired" count too, so the assertion looks
    # for the badge inside the row rather than anywhere on the page.
    assert_equal ["Already expired"], rendered_expired_badges
  end

  test "a ticket expiring this year is not flagged" do
    ticket_for(@admin)

    get ticketing_expiring_path

    assert_response :success
    assert_empty rendered_expired_badges
  end

  test "the header counts split the report by already-expired" do
    ticket_for(@admin)
    ticket_for(@ticketing)
    ticket_for(@outsider, expiry_date: "#{YEAR - 2}-09-15")

    get ticketing_expiring_path

    assert_response :success
    assert_equal({ "Expiring Tickets" => "3", "Expires This Year" => "2", "Already Expired" => "1" },
                 rendered_stats)
  end

  # The counts describe the whole report, so a filter must not move them.
  test "the header counts ignore the filters" do
    ticket_for(@admin)
    ticket_for(@ticketing, expiry_date: "#{YEAR - 1}-09-15")

    get ticketing_expiring_path(expired: "yes")

    assert_response :success
    assert_equal [@ticketing.callsign], rendered_callsigns
    assert_equal({ "Expiring Tickets" => "2", "Expires This Year" => "1", "Already Expired" => "1" },
                 rendered_stats)
  end

  # --- filters --------------------------------------------------------------

  test "the ticket status filter narrows the list either way" do
    ticket_for(@admin)
    ticket_for(@ticketing, status: AccessDocument::BANKED)

    get ticketing_expiring_path(status: AccessDocument::BANKED)

    assert_response :success
    assert_equal [@ticketing.callsign], rendered_callsigns
    # Y stays the whole report so the filter visibly narrows X against it.
    assert_match "Showing 1 of 2 expiring tickets", response.body

    get ticketing_expiring_path(status: AccessDocument::QUALIFIED)

    assert_response :success
    assert_equal [@admin.callsign], rendered_callsigns
  end

  test "the type filter narrows the list to that type" do
    ticket_for(@admin)
    credential = ticket_for(@ticketing, type: AccessDocument::STAFF_CREDENTIAL)

    get ticketing_expiring_path(type: AccessDocument::STAFF_CREDENTIAL)

    assert_response :success
    assert_equal [credential.person.callsign], rendered_callsigns
    assert_match "Showing 1 of 2 expiring tickets", response.body
  end

  test "the already-expired filter narrows the list either way" do
    ticket_for(@admin)
    ticket_for(@ticketing, expiry_date: "#{YEAR - 1}-09-15")

    get ticketing_expiring_path(expired: "no")

    assert_response :success
    assert_equal [@admin.callsign], rendered_callsigns

    get ticketing_expiring_path(expired: "yes")

    assert_response :success
    assert_equal [@ticketing.callsign], rendered_callsigns
  end

  test "the filters narrow together" do
    ticket_for(@admin, status: AccessDocument::BANKED)
    ticket_for(@outsider, type: AccessDocument::STAFF_CREDENTIAL)
    ticket_for(@ticketing, status: AccessDocument::BANKED,
                           type: AccessDocument::STAFF_CREDENTIAL)

    get ticketing_expiring_path(status: AccessDocument::BANKED,
                                type: AccessDocument::STAFF_CREDENTIAL, expired: "no")

    assert_response :success
    assert_equal [@ticketing.callsign], rendered_callsigns
  end

  # A hand-edited URL must not be able to empty the page or park a bogus label
  # in the filter bar, so an unknown value falls back to showing everything.
  test "an unknown filter value falls back to no filter" do
    ticket_for(@admin)
    ticket_for(@ticketing, type: AccessDocument::STAFF_CREDENTIAL)

    get ticketing_expiring_path(status: "bogus", type: "bogus", expired: "bogus")

    assert_response :success
    assert_equal [@admin.callsign, @ticketing.callsign].sort, rendered_callsigns.sort
    assert_match "Showing 2 of 2 expiring tickets", response.body
  end

  test "the empty report says so" do
    get ticketing_expiring_path

    assert_response :success
    assert_match "No tickets expire this year", response.body
  end

  # --- CSV export -----------------------------------------------------------

  test "the csv export returns the filtered rows under the expected filename" do
    ticket = ticket_for(@admin)
    ticket_for(@ticketing, status: AccessDocument::BANKED)

    get ticketing_expiring_path(format: :csv, status: AccessDocument::QUALIFIED)

    assert_response :success
    assert_equal "text/csv", response.media_type
    assert_match %(filename="#{YEAR}-expiring-access-documents.csv"), response.headers["Content-Disposition"]

    lines = response.body.split("\n")
    assert_equal "Callsign,Status,Email,RAD,Ticket Type,Ticket Status,Expires After", lines.first
    assert_equal 2, lines.size, "only the filtered row belongs in the export"
    assert_equal [@admin.callsign, @admin.status, @admin.email, "RAD-#{ticket.id}",
                  "Special Price Ticket", AccessDocument::QUALIFIED,
                  ticket.expiry_date.year].join(","),
                 lines.second
    assert_not_includes response.body, @ticketing.callsign
  end

  private

  # A qualified special price ticket running out at the end of this year: the
  # plainest thing the report is meant to list. delivery_method is spelled out
  # because the column is NOT NULL and the model only fills it in on a status
  # change, as the fixtures do.
  def ticket_for(holder, type: AccessDocument::SPT, status: AccessDocument::QUALIFIED, **attributes)
    AccessDocument.create!(person: holder, type:, status:, source_year: YEAR - 2,
                           delivery_method: AccessDocument::DELIVERY_NONE,
                           expiry_date: "#{YEAR}-09-15", **attributes)
  end

  # The stat row above the table, as { label => value }.
  def rendered_stats
    css_select("div.rounded-lg.p-3.text-center").to_h do |box|
      parts = box.css("div")
      [parts.last.text.strip, parts.first.text.strip]
    end
  end

  # The callsign link opening each rendered row of the table.
  def rendered_callsigns
    css_select("tbody th a").map { |link| link.text.strip }
  end

  # The Expires After cell closing each rendered row.
  def rendered_expiry_years
    css_select("tbody tr").map { |row| row.css("td").last.text.strip }
  end

  # The already-expired badges rendered in the table body.
  def rendered_expired_badges
    css_select("tbody .badge").map { |badge| badge.text.strip }
  end
end
