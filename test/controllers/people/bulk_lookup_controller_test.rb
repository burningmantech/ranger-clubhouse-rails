# frozen_string_literal: true

require "test_helper"

class People::BulkLookupControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include DomIdTestHelper

  setup do
    Rails.cache.clear
    Current.reset

    @admin = person(:active_ranger)
    @outsider = person(:inactive_ranger)

    ensure_role(Role::ADMIN, "Admin")
    grant_role(@admin, Role::ADMIN)

    sign_in_as(@admin)
  end

  teardown do
    Current.reset
    Rails.cache.clear
  end

  # ---------------------------------------------------------------- access

  test "an admin reaches the form" do
    get people_bulk_lookup_path

    assert_response :success
    assert_select "h1", /Bulk Lookup/
    assert_select "textarea[name=lines]"
    assert_unique_dom_ids
  end

  test "someone without the admin role is turned away" do
    sign_in_as(@outsider)

    get people_bulk_lookup_path

    assert_redirected_to me_root_path
    assert_match(/admin role required/i, flash[:error])
  end

  test "the lookup itself is refused without the admin role" do
    sign_in_as(@outsider)

    post people_run_bulk_lookup_path, params: { lines: "TestRanger" }

    assert_redirected_to me_root_path
    assert_match(/admin role required/i, flash[:error])
  end

  # ---------------------------------------------------------------- lookup

  test "a callsign matches with capitalisation and punctuation ignored" do
    post people_run_bulk_lookup_path, params: { lines: "  test-RANGER!!  " }

    assert_response :unprocessable_entity
    assert_select "[data-controller=scroll-to-top]"
    assert_select "#found-section tbody tr", 1
    assert_select "#found-section", /TestRanger/
    assert_select "#not-found-section", false
  end

  test "a line with an @ matches by email address" do
    post people_run_bulk_lookup_path, params: { lines: "TESTRANGER@EXAMPLE.COM" }

    assert_response :unprocessable_entity
    assert_select "#found-section", /TestRanger/
  end

  test "an email pasted with an invisible trailing space still matches" do
    post people_run_bulk_lookup_path, params: { lines: "testranger@example.com " }

    assert_select "#found-section", /TestRanger/
    assert_select "#not-found-section", false
  end

  test "an unknown email stays a miss even when its name part is a callsign" do
    post people_run_bulk_lookup_path, params: { lines: "testranger@nowhere.com" }

    assert_select "#found-section", false
    assert_select "#not-found-section", /testranger@nowhere\.com/
  end

  test "misses and punctuation-only lines are reported back verbatim" do
    post people_run_bulk_lookup_path,
         params: { lines: "TestRanger\nWrangler\n!!!\ninactive@example.com" }

    assert_select "#found-section tbody tr", 2
    assert_select "#not-found-section", /Wrangler/
    assert_select "#not-found-section", /!!!/
    assert_unique_dom_ids
  end

  test "blank lines are ignored" do
    post people_run_bulk_lookup_path, params: { lines: "\n\nTestRanger\n\n" }

    assert_select "#found-section tbody tr", 1
    assert_select "#not-found-section", false
  end

  test "a repeated line gets a row each time" do
    post people_run_bulk_lookup_path, params: { lines: "TestRanger\nTestRanger" }

    assert_select "#found-section tbody tr", 2
  end

  test "a record whose stored key is not lowercase still matches" do
    # Long-standing records carry mixed-case keys; the database forgives the
    # case and the lookup has to as well.
    @outsider.update_columns(callsign: "OldTimer", callsign_normalized: "OldTimer")

    post people_run_bulk_lookup_path, params: { lines: "old-timer" }

    assert_select "#found-section", /OldTimer/
    assert_select "#not-found-section", false
  end

  test "a callsign shared by two people is flagged, not guessed" do
    @outsider.update_columns(callsign: "Test-Ranger", callsign_normalized: "testranger")

    post people_run_bulk_lookup_path, params: { lines: "TestRanger" }

    assert_select "#found-section", false
    assert_select "#ambiguous-lines", /TestRanger/
    assert_select "#not-found-section", /match more than one person/
  end

  test "someone who never rangered shows never and zero years" do
    post people_run_bulk_lookup_path, params: { lines: "ProspectiveNewbie" }

    assert_select "#found-section tbody tr", 1
    assert_select "#found-section em", "never"
    assert_select "#found-section", /ProspectiveNewbie/
  end

  test "training and echelon years do not count as rangered years" do
    # EchelonTest has a 2024 entry on record but no rangered years, so the
    # rangered columns must say never rather than 2024.
    post people_run_bulk_lookup_path, params: { lines: "EchelonTest" }

    assert_select "#found-section tbody tr", 1
    assert_select "#found-section em", "never"
  end

  # -------------------------------------------------------------- refusals

  test "a whitespace-only submission is refused, not reported as no matches" do
    post people_run_bulk_lookup_path, params: { lines: "   \n\n  " }

    assert_response :unprocessable_entity
    assert_select "textarea[name=lines]"
    assert_match(/enter at least one callsign/i, response.body)
    assert_select "#found-section", false
    assert_select "[data-controller=scroll-to-top]", false
  end

  test "a list past the line ceiling is refused" do
    lines = Array.new(People::BulkLookupController::MAX_LINES + 1, "TestRanger").join("\n")

    post people_run_bulk_lookup_path, params: { lines: }

    assert_response :unprocessable_entity
    assert_match(/split it into lists/i, response.body)
    assert_select "#found-section", false
  end

  test "a lines parameter that is not plain text is refused, not echoed" do
    post people_run_bulk_lookup_path, params: { lines: ["TestRanger", "Wrangler"] }

    assert_response :unprocessable_entity
    assert_match(/enter at least one callsign/i, response.body)
    assert_no_match(/\["TestRanger"/, response.body)
  end

  # ------------------------------------------------------------------- csv

  test "the found export carries the full record set" do
    @outsider.update!(vintage: true, home_phone: "+15105551212")

    post people_run_bulk_lookup_path(format: :csv),
         params: { lines: "TestRanger\nInactiveRanger\nWrangler", subset: "found" }

    assert_response :success
    assert_match(/bulk-lookup-found\.csv/, response.header["Content-Disposition"])

    rows = response.body.split("\n")
    assert_equal "Callsign,Legal First Name,Preferred Name,Last Name,Status,Email," \
                 "Last Rangered,Vintage,Years Rangered,Address,Apt,Address 2,City," \
                 "State,Postal Code,Country,Home Phone",
                 rows.first

    cells = rows.detect { |row| row.start_with?("TestRanger,") }.split(",")
    assert_equal "2024", cells[6]
    assert_equal "N", cells[7]
    assert_equal "2", cells[8]

    vintage_cells = rows.detect { |row| row.start_with?("InactiveRanger,") }.split(",")
    assert_equal "Y", vintage_cells[7]
    # Formatted so a spreadsheet reads it as text, never as a formula.
    assert_equal "(510) 555-1212", vintage_cells.last

    assert_not rows.any? { |row| row.start_with?("Wrangler") }
  end

  test "someone with no rangered years exports the word never" do
    post people_run_bulk_lookup_path(format: :csv),
         params: { lines: "ProspectiveNewbie", subset: "found" }

    cells = response.body.split("\n").second.split(",")
    assert_equal "never", cells[6]
    assert_equal "0", cells[8]
  end

  test "the not found export lists the misses alone" do
    post people_run_bulk_lookup_path(format: :csv),
         params: { lines: "TestRanger\nWrangler", subset: "not_found" }

    assert_response :success
    assert_match(/bulk-lookup-not-found\.csv/, response.header["Content-Disposition"])
    assert_equal ["Not Found Callsign/Email", "Wrangler"], response.body.split("\n")
  end

  test "an export that does not name a list is refused" do
    post people_run_bulk_lookup_path(format: :csv),
         params: { lines: "TestRanger", subset: "everything" }

    assert_response :bad_request
  end

  test "an export of a refused lookup is refused too" do
    post people_run_bulk_lookup_path(format: :csv), params: { lines: "", subset: "found" }

    assert_response :unprocessable_entity
  end
end
