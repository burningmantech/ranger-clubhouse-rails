# frozen_string_literal: true

require "test_helper"

# Ticketing > Unclaimed with Sign-Ups: the qualified-regular-ticket report, the
# August 15th sign-up flag, the two filters, and the CSV export.
#
# The action reads the whole access_document table and the shared fixtures
# belong to other suites, so every test starts from an empty table and builds
# exactly the documents it needs.
class Ticketing::UnclaimedWithSignupsControllerTest < ActionDispatch::IntegrationTest
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

    get ticketing_unclaimed_with_signups_path

    assert_response :success
    assert_equal [@admin.callsign], rendered_callsigns
    assert_select "a[href=?]", person_path(@admin), text: @admin.callsign
    assert_match "Showing 1 of 1 unclaimed ticket", response.body
  end

  test "the report renders with only the edit access documents role" do
    sign_in_as(@ticketing)
    ticket_for(@ticketing)

    get ticketing_unclaimed_with_signups_path

    assert_response :success
    assert_equal [@ticketing.callsign], rendered_callsigns
  end

  test "the report is refused without the admin or edit access documents role" do
    sign_in_as(@outsider)

    get ticketing_unclaimed_with_signups_path

    assert_redirected_to me_root_path
    assert_equal "Admin or Edit Access Documents role required to view ticketing reports.", flash[:error]
  end

  # --- what counts as an unclaimed ticket ----------------------------------

  test "only qualified regular tickets are listed" do
    spt = ticket_for(@admin)
    credential = ticket_for(@ticketing, type: AccessDocument::STAFF_CREDENTIAL)

    # Same types, further along the pipeline.
    (AccessDocument::CURRENT_STATUSES - [AccessDocument::QUALIFIED]).each do |status|
      ticket_for(@outsider, status:)
    end
    # Qualified, but not a regular ticket.
    ticket_for(@outsider, type: AccessDocument::GIFT)
    ticket_for(@outsider, type: AccessDocument::SAP)

    get ticketing_unclaimed_with_signups_path

    assert_response :success
    assert_equal [spt.person.callsign, credential.person.callsign].sort, rendered_callsigns.sort
    assert_match "Showing 2 of 2 unclaimed tickets", response.body
  end

  test "rows are sorted by callsign regardless of case" do
    ticket_for(@ticketing)
    ticket_for(@admin)

    get ticketing_unclaimed_with_signups_path

    assert_response :success
    expected = [@admin, @ticketing].map(&:callsign).sort_by(&:downcase)
    assert_equal expected, rendered_callsigns
  end

  # --- the August 15th sign-up flag ----------------------------------------

  test "a shift starting on or after the cutoff counts as a sign-up" do
    ticket_for(@admin)
    sign_up(@admin, Time.local(YEAR, 8, 15, 12, 0, 0))

    get ticketing_unclaimed_with_signups_path

    assert_response :success
    assert_equal ["Yes"], rendered_signup_flags
    assert_match "Signed Up for a Shift", response.body
  end

  test "a shift starting before the cutoff does not count as a sign-up" do
    ticket_for(@admin)
    sign_up(@admin, Time.local(YEAR, 8, 14, 12, 0, 0))

    get ticketing_unclaimed_with_signups_path

    assert_response :success
    assert_equal ["No"], rendered_signup_flags
  end

  # begins_year is what scopes the report to now, so a late-August shift from
  # another year must not light the flag up.
  test "a late shift in another year does not count as a sign-up" do
    ticket_for(@admin)
    sign_up(@admin, Time.local(YEAR - 1, 8, 20, 12, 0, 0))

    get ticketing_unclaimed_with_signups_path

    assert_response :success
    assert_equal ["No"], rendered_signup_flags
  end

  test "the header counts split the report by sign-up" do
    ticket_for(@admin)
    ticket_for(@ticketing)
    ticket_for(@outsider)
    sign_up(@admin, Time.local(YEAR, 8, 20, 9, 0, 0))

    get ticketing_unclaimed_with_signups_path

    assert_response :success
    assert_equal({ "Unclaimed Tickets" => "3", "Signed Up for a Shift" => "1", "No Sign-Up" => "2" },
                 rendered_stats)
    assert_equal 2, rendered_signup_flags.count("No")
    assert_equal 1, rendered_signup_flags.count("Yes")
  end

  # The counts describe the whole report, so a filter must not move them.
  test "the header counts ignore the filters" do
    ticket_for(@admin)
    ticket_for(@ticketing)
    sign_up(@admin, Time.local(YEAR, 8, 20, 9, 0, 0))

    get ticketing_unclaimed_with_signups_path(signup: "yes")

    assert_response :success
    assert_equal [@admin.callsign], rendered_callsigns
    assert_equal({ "Unclaimed Tickets" => "2", "Signed Up for a Shift" => "1", "No Sign-Up" => "1" },
                 rendered_stats)
  end

  # --- filters --------------------------------------------------------------

  test "the sign-up filter narrows the list either way" do
    ticket_for(@admin)
    ticket_for(@ticketing)
    sign_up(@admin, Time.local(YEAR, 8, 20, 9, 0, 0))

    get ticketing_unclaimed_with_signups_path(signup: "yes")

    assert_response :success
    assert_equal [@admin.callsign], rendered_callsigns
    # Y stays the whole report so the filter visibly narrows X against it.
    assert_match "Showing 1 of 2 unclaimed tickets", response.body

    get ticketing_unclaimed_with_signups_path(signup: "no")

    assert_response :success
    assert_equal [@ticketing.callsign], rendered_callsigns
  end

  test "the type filter narrows the list to that type" do
    ticket_for(@admin)
    credential = ticket_for(@ticketing, type: AccessDocument::STAFF_CREDENTIAL)

    get ticketing_unclaimed_with_signups_path(type: AccessDocument::STAFF_CREDENTIAL)

    assert_response :success
    assert_equal [credential.person.callsign], rendered_callsigns
    assert_match "Showing 1 of 2 unclaimed tickets", response.body
  end

  test "the sign-up and type filters narrow together" do
    ticket_for(@admin)
    ticket_for(@outsider, type: AccessDocument::STAFF_CREDENTIAL)
    ticket_for(@ticketing, type: AccessDocument::STAFF_CREDENTIAL)
    sign_up(@admin, Time.local(YEAR, 8, 20, 9, 0, 0))
    sign_up(@ticketing, Time.local(YEAR, 8, 20, 9, 0, 0))

    get ticketing_unclaimed_with_signups_path(signup: "yes", type: AccessDocument::STAFF_CREDENTIAL)

    assert_response :success
    assert_equal [@ticketing.callsign], rendered_callsigns
  end

  # A hand-edited URL must not be able to empty the page or park a bogus label
  # in the filter bar, so an unknown value falls back to showing everything.
  test "an unknown sign-up or type falls back to no filter" do
    ticket_for(@admin)
    ticket_for(@ticketing, type: AccessDocument::STAFF_CREDENTIAL)

    get ticketing_unclaimed_with_signups_path(signup: "bogus", type: "bogus")

    assert_response :success
    assert_equal [@admin.callsign, @ticketing.callsign].sort, rendered_callsigns.sort
    assert_match "Showing 2 of 2 unclaimed tickets", response.body
  end

  test "the empty report says so" do
    get ticketing_unclaimed_with_signups_path

    assert_response :success
    assert_match "Every ticket has been claimed", response.body
  end

  # --- CSV export -----------------------------------------------------------

  test "the csv export returns the filtered rows under the expected filename" do
    ticket = ticket_for(@admin)
    ticket_for(@ticketing, type: AccessDocument::STAFF_CREDENTIAL)
    sign_up(@admin, Time.local(YEAR, 8, 20, 9, 0, 0))

    get ticketing_unclaimed_with_signups_path(format: :csv, signup: "yes")

    assert_response :success
    assert_equal "text/csv", response.media_type
    assert_match %(filename="#{YEAR}-unclaimed-tickets.csv"), response.headers["Content-Disposition"]

    lines = response.body.split("\n")
    assert_equal "Callsign,Status,Email,Type,RAD,Expires,Has Sign Up", lines.first
    assert_equal 2, lines.size, "only the filtered row belongs in the export"
    assert_equal [@admin.callsign, @admin.status, @admin.email, "Special Price Ticket",
                  "RAD-#{ticket.id}", ticket.expiry_date.iso8601, "Y"].join(","),
                 lines.second
    assert_not_includes response.body, @ticketing.callsign
  end

  test "the csv export marks a missing sign-up with N" do
    ticket_for(@admin)

    get ticketing_unclaimed_with_signups_path(format: :csv)

    assert_response :success
    assert_equal "N", response.body.split("\n").second.split(",").last
  end

  private

  # A qualified special price ticket by default: the plainest thing the report
  # is meant to list. delivery_method is spelled out because the column is NOT
  # NULL and the model only fills it in on a status change, as the fixtures do.
  def ticket_for(holder, type: AccessDocument::SPT, status: AccessDocument::QUALIFIED, **attributes)
    AccessDocument.create!(person: holder, type:, status:, source_year: YEAR,
                           delivery_method: AccessDocument::DELIVERY_NONE,
                           expiry_date: "#{YEAR + 3}-09-15", **attributes)
  end

  # slot.begins is stored as machine-local wall clock, so the times a test
  # compares against the cutoff are built the same way the report builds it.
  def sign_up(holder, begins)
    slot = Slot.create!(position: positions(:training_lead),
                        begins:, ends: begins + 4.hours, max: 10, active: true)
    PersonSlot.create!(person: holder, slot:)
  end

  # The stat row above the table, as { label => value }.
  def rendered_stats
    css_select("div.rounded-lg.p-3.text-center").to_h do |box|
      parts = box.css("div")
      [parts.last.text.strip, parts.first.text.strip]
    end
  end

  # The callsign heading each rendered row of the table.
  def rendered_callsigns
    css_select("tbody th").map { |cell| cell.text.strip }
  end

  # The Yes/No badge closing each rendered row.
  def rendered_signup_flags
    css_select("tbody tr").map { |row| row.css("td").last.text.strip }
  end
end
