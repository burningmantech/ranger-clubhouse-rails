# frozen_string_literal: true

require "test_helper"

class Vc::ApplicationImportControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include ActiveSupport::Testing::TimeHelpers
  include FakeSalesforceConnectorHelper

  setup do
    travel_to Time.zone.local(2026, 4, 16, 12, 0, 0)
    Rails.cache.clear
    Current.reset

    @admin = person(:active_ranger)
    @importer = person(:auditor_ranger)
    @vc = person(:echelon_ranger)
    @outsider = person(:inactive_ranger)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::VC, "Volunteer Coordinator")
    ensure_role(Role::SALESFORCE_IMPORT, "Salesforce Import")
    grant_role(@admin, Role::ADMIN)
    grant_role(@vc, Role::VC)
    grant_role(@importer, Role::SALESFORCE_IMPORT)
  end

  teardown do
    Current.reset
    travel_back
    Rails.cache.clear
  end

  # --- authorization -------------------------------------------------------

  test "requires the Admin or Salesforce Import role" do
    [@outsider, @vc].each do |person|
      sign_in_as(person)

      get vc_application_import_path
      assert_redirected_to me_root_path

      post vc_application_import_commit_path
      assert_redirected_to me_root_path
    end
  end

  test "admin can open the page" do
    sign_in_as(@admin)

    get vc_application_import_path

    assert_response :success
    assert_match "Salesforce Application Import", response.body
  end

  test "the salesforce import role can open the page" do
    sign_in_as(@importer)

    get vc_application_import_path

    assert_response :success
  end

  # --- index ---------------------------------------------------------------

  test "the index never contacts Salesforce and shows no results" do
    sign_in_as(@admin)

    fake = FakeSalesforceConnector.new
    with_fake_connector(fake) { get vc_application_import_path }

    assert_response :success
    assert_empty fake.queries
    assert_no_match "Applications Ready to Import", response.body
  end

  # --- preview -------------------------------------------------------------

  test "preview renders the ledger at 422 and saves nothing" do
    sign_in_as(@admin)
    fake = one_page_connector

    assert_no_difference(%w[ProspectiveApplication.count ProspectiveApplicationLog.count
                            ProspectiveApplicationNote.count]) do
      with_fake_connector(fake) { post vc_application_import_preview_path }
    end

    assert_response :unprocessable_entity
    assert_match "Preview only", response.body
    assert_match "Applications Ready to Import", response.body
    assert_match "R-5001", response.body
  end

  test "the preview application table offers a CSV holding the applicant email" do
    sign_in_as(@admin)

    with_fake_connector(one_page_connector) { post vc_application_import_preview_path }

    link = css_select("a[download='salesforce-preview-applications.csv']").first
    assert link, "expected a CSV download link on the preview table"
    csv = CGI.unescape(link["href"].delete_prefix("data:text/csv;charset=utf-8,"))
    assert_match "Email", csv
    assert_match "terra.firma@example.com", csv
  end

  # --- commit --------------------------------------------------------------

  test "commit imports the applications and renders the ledger" do
    sign_in_as(@importer)
    fake = one_page_connector

    assert_difference "ProspectiveApplication.count", 1 do
      assert_difference "ProspectiveApplicationLog.count", 1 do
        with_fake_connector(fake) { post vc_application_import_commit_path }
      end
    end

    assert_response :unprocessable_entity
    assert_match "Imported Applications", response.body
    assert_match "imported into the Clubhouse", response.body

    row = ProspectiveApplication.find_by!(year: 2026, salesforce_name: "R-5001")
    assert_match "A-#{row.id}", response.body
  end

  # --- failure states ------------------------------------------------------

  test "a Salesforce sign-in failure renders the error callout" do
    sign_in_as(@admin)

    # No connector stub: the test database has no SFprd* settings, so the
    # real connector fails auth before any network traffic.
    post vc_application_import_preview_path

    assert_response :unprocessable_entity
    assert_match "Could Not Sign In to Salesforce", response.body
    assert_match "SFprdAuthUrl", response.body
  end

  test "query failures render their table with the CSV download" do
    sign_in_as(@admin)
    fake = FakeSalesforceConnector.new(query_results: [
      FakeSalesforceConnector.envelope(FakeSalesforceConnector.application_record),
      FakeSalesforceConnector.envelope # contact hidden by USER_MODE
    ])

    with_fake_connector(fake) { post vc_application_import_preview_path }

    assert_response :unprocessable_entity
    assert_match "Salesforce Query Failures", response.body
    assert_match "Contact record is inaccessible", response.body
    assert_match "Download CSV", response.body
    assert_match "data:text/csv", response.body
  end

  test "a mid-run query failure shows the partial results warning" do
    sign_in_as(@admin)
    fake = FakeSalesforceConnector.new(
      query_results: [
        FakeSalesforceConnector.envelope(FakeSalesforceConnector.application_record),
        FakeSalesforceConnector.envelope(FakeSalesforceConnector.contact_record("a01SF001")),
        false
      ]
    )

    with_fake_connector(fake) { post vc_application_import_preview_path }

    assert_response :unprocessable_entity
    assert_match "The Salesforce Pull Did Not Finish", response.body
    assert_match "R-5001", response.body, "partial results still render"
  end

  private

  def one_page_connector
    FakeSalesforceConnector.new(query_results: [
      FakeSalesforceConnector.envelope(FakeSalesforceConnector.application_record),
      FakeSalesforceConnector.envelope(FakeSalesforceConnector.contact_record("a01SF001"))
    ])
  end
end
