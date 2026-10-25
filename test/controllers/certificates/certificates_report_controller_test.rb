# frozen_string_literal: true

require "test_helper"

class Certificates::CertificatesReportControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include DomIdTestHelper

  # CPR is held by an active ranger (with a card number), a retired ranger
  # (without one), and a bonked ranger. Bonked is not an active status, so the
  # report should see two people, one card number, one missing.
  setup do
    Rails.cache.clear
    Current.reset

    @admin = person(:echelon_ranger)
    @cert_manager = person(:ranger_with_custom_gender)
    @outsider = person(:plate_collision_ranger)

    @cpr = certification(:cpr)
    @ham = certification(:ham_radio)
    @wfa = certification(:wilderness_first_aid)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::CERTIFICATION_MGMT, "Certification Management")

    grant_role(@admin, Role::ADMIN)
    grant_role(@cert_manager, Role::CERTIFICATION_MGMT)
  end

  teardown do
    Current.reset
    Rails.cache.clear
  end

  # --- access ---------------------------------------------------------------

  test "admin may read both levels" do
    sign_in_as(@admin)

    get certificates_report_path
    assert_response :success

    get certificates_report_detail_path(@cpr)
    assert_response :success
  end

  test "certification management may read both levels" do
    sign_in_as(@cert_manager)

    get certificates_report_path
    assert_response :success

    get certificates_report_detail_path(@cpr)
    assert_response :success
  end

  test "a person without either role is turned away from both levels" do
    sign_in_as(@outsider)

    get certificates_report_path
    assert_redirected_to me_root_path

    get certificates_report_detail_path(@cpr)
    assert_redirected_to me_root_path
  end

  test "a signed out visitor is sent to login" do
    get certificates_report_path
    assert_redirected_to root_path
  end

  # --- index ----------------------------------------------------------------

  test "index lists every certification including one no one holds" do
    sign_in_as(@admin)
    get certificates_report_path

    assert_response :success
    assert_select "a[href=?]", certificates_report_detail_path(@cpr)
    assert_select "a[href=?]", certificates_report_detail_path(@ham)
    assert_select "a[href=?]", certificates_report_detail_path(@wfa)
    assert_match "0 people", response.body
  end

  test "index counts leave out holders whose status is not active" do
    sign_in_as(@admin)
    get certificates_report_path

    # CPR has three records but only two active-status holders.
    assert_select "a[href=?]", certificates_report_detail_path(@cpr) do
      assert_select "*", text: /2 people/
    end
    assert_match "Showing 3 certifications with 3 records", response.body.squish
  end

  test "index renders unique dom ids" do
    sign_in_as(@admin)
    get certificates_report_path

    assert_unique_dom_ids
  end

  # --- detail ---------------------------------------------------------------

  test "detail lists active-status holders in callsign order" do
    sign_in_as(@admin)
    get certificates_report_detail_path(@cpr)

    assert_response :success
    callsigns = roster_callsigns
    assert_equal ["RetiredRanger", "TestRanger"], callsigns
  end

  test "detail leaves out a holder whose status is not active" do
    # Proves the bonked person's record is really there to be left out, so the
    # assertions below cannot pass just because the fixture went missing.
    assert_equal 3, PersonCertification.where(certification_id: @cpr.id).count
    assert_equal "bonked", person(:bonked_ranger).status

    sign_in_as(@admin)
    get certificates_report_detail_path(@cpr)

    assert_no_match "BonkedTest", response.body
    assert_no_match "CPR-BONKED", response.body
    assert_equal 2, css_select("tbody tr").size
  end

  test "detail shows the dates and card number" do
    sign_in_as(@admin)
    get certificates_report_detail_path(@cpr)

    assert_match "CPR-12345", response.body
    assert_match "2026-03-01", response.body
    assert_match "2026-02-15", response.body
    assert_match "Renewed at spring training.", response.body
  end

  test "detail counts people, cards on file, and cards missing" do
    sign_in_as(@admin)
    get certificates_report_detail_path(@cpr)

    # Two holders, one of whom came with a card number.
    stats = css_select("div.rounded-lg.text-center").map { |box| box.text.squish }
    assert_includes stats, "2People"
    assert_includes stats, "1Card Number on File"
    assert_includes stats, "1Missing Card Number"
  end

  test "detail hides the missing-card count when every holder has one" do
    person_certification(:retired_ranger_cpr).update!(card_number: "CPR-99999")

    sign_in_as(@admin)
    get certificates_report_detail_path(@cpr)

    assert_no_match "Missing Card Number", response.body
  end

  test "detail status filter narrows the roster" do
    sign_in_as(@admin)
    get certificates_report_detail_path(@cpr, status: "retired")

    assert_response :success
    callsigns = roster_callsigns
    assert_equal ["RetiredRanger"], callsigns
    assert_match "Showing 1 of 2 people", response.body
  end

  test "detail ignores a status that no one in the roster holds" do
    sign_in_as(@admin)
    get certificates_report_detail_path(@cpr, status: "bonked")

    assert_response :success
    callsigns = roster_callsigns
    assert_equal ["RetiredRanger", "TestRanger"], callsigns
    assert_select "a", text: /Status: bonked/, count: 0
  end

  test "detail of a certification no one holds says so" do
    sign_in_as(@admin)
    get certificates_report_detail_path(@wfa)

    assert_response :success
    assert_match "No one with an active status holds this certification.", response.body
  end

  test "detail of an unknown certification is not found" do
    sign_in_as(@admin)
    get certificates_report_detail_path(id: 999_999)

    assert_response :not_found
  end

  # find casts "1-cpr" to 1, so without the route constraint one page would
  # answer to any number of spellings and then repeat them back in its links.
  test "an id that is not a plain number does not reach the report" do
    sign_in_as(@admin)
    get "/certificates/certificates-report/#{@cpr.id}-cpr"

    assert_response :not_found
  end

  test "someone holding a certification twice is counted once" do
    PersonCertification.create!(person_id: person(:active_ranger).id,
                                certification_id: @cpr.id,
                                card_number: "CPR-SECOND")

    sign_in_as(@admin)
    get certificates_report_detail_path(@cpr)

    stats = css_select("div.rounded-lg.text-center").map { |box| box.text.squish }
    assert_includes stats, "2People", "the roster still holds two people, not three records"
    assert_match "Showing 2 of 2 people", response.body
  end

  test "detail renders unique dom ids" do
    sign_in_as(@admin)
    get certificates_report_detail_path(@cpr)

    assert_unique_dom_ids
  end

  # --- names and email ------------------------------------------------------

  test "a reader without the personal information roles sees no name column" do
    sign_in_as(@cert_manager)
    get certificates_report_detail_path(@cpr)

    assert_response :success
    # Anchored on the full column list: asserting only the absence of "Name"
    # would also pass if the table stopped rendering altogether.
    headings = css_select("thead th").map { |cell| cell.text.strip }
    assert_equal ["Callsign", "Status", "Issued On", "Trained On", "Card/Certificate #", "Notes"], headings
  end

  # --- csv ------------------------------------------------------------------

  test "index csv carries a column group per certification" do
    sign_in_as(@admin)
    get certificates_report_path(format: :csv)

    assert_response :success
    assert_equal "text/csv; charset=utf-8", response.content_type
    header, *rows = response.body.lines.map(&:chomp)

    assert_match(/^Callsign,Status,Name,Email,/, header)
    assert_match "Card/Certificate #", header
    assert_equal 2, rows.size, "only active-status holders get a row"
    assert_match "CPR-12345", rows.join("\n")
    assert_no_match(/BonkedTest/, response.body)
    assert_match "certificates-report.csv", response.headers["Content-Disposition"]
  end

  test "detail csv holds one row per person in the roster" do
    sign_in_as(@admin)
    get certificates_report_detail_path(@cpr, format: :csv)

    assert_response :success
    header, *rows = response.body.lines.map(&:chomp)
    assert_match(/^Callsign,Status,Name,Email,Issued On,Trained On,Card\/Certificate #,Notes$/, header)
    assert_equal 2, rows.size
    assert_match "certificates-report-cpr.csv", response.headers["Content-Disposition"]
  end

  test "detail csv honors the status filter" do
    sign_in_as(@admin)
    get certificates_report_detail_path(@cpr, status: "retired", format: :csv)

    _header, *rows = response.body.lines.map(&:chomp)
    assert_equal 1, rows.size
    assert_match "RetiredRanger", rows.first
  end

  test "csv leaves out name and email for a reader without those roles" do
    sign_in_as(@cert_manager)
    get certificates_report_detail_path(@cpr, format: :csv)

    header = response.body.lines.first.chomp
    assert_equal "Callsign,Status,Issued On,Trained On,Card/Certificate #,Notes", header
  end

  private

  # The callsign is the row's header cell, not a plain cell.
  def roster_callsigns
    css_select("tbody tr th:first-child").map { |cell| cell.text.strip }
  end
end
