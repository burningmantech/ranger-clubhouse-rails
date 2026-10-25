# frozen_string_literal: true

require "test_helper"

class Vc::CreateProspectivesControllerTest < ActionDispatch::IntegrationTest
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

      get vc_create_prospectives_path
      assert_redirected_to me_root_path

      post vc_create_prospectives_commit_path
      assert_redirected_to me_root_path
    end
  end

  test "admin can open the page" do
    sign_in_as(@admin)

    get vc_create_prospectives_path

    assert_response :success
    assert_match "Create Prospective Accounts", response.body
  end

  test "the salesforce import role can open the page" do
    sign_in_as(@importer)

    get vc_create_prospectives_path

    assert_response :success
  end

  # --- index ---------------------------------------------------------------

  test "the index runs no checks and shows no results" do
    sign_in_as(@admin)

    get vc_create_prospectives_path

    assert_response :success
    assert_no_match "Preview only", response.body
    assert_no_match "Ready to Create", response.body
  end

  test "the page states whether welcome emails and Salesforce updates are on" do
    sign_in_as(@admin)

    get vc_create_prospectives_path
    assert_match "No welcome emails are sent", response.body
    assert_match "Salesforce is not contacted at all", response.body

    Setting.create!(name: Setting::SEND_WELCOME_EMAIL, value: "true")
    Rails.cache.clear

    get vc_create_prospectives_path
    assert_match "emailed a welcome message", response.body
  end

  # --- preview -------------------------------------------------------------

  test "preview renders the results at 422 and creates nothing" do
    sign_in_as(@admin)

    assert_no_difference %w[Person.count PersonStatus.count] do
      post vc_create_prospectives_preview_path
    end

    assert_response :unprocessable_entity
    assert_match "Preview only", response.body
    assert_match "Ready to Create", response.body
    assert_match "A-#{prospective_application(:approved_ready).id}", response.body
    assert_equal ProspectiveApplication::STATUS_APPROVED,
                 prospective_application(:approved_ready).reload.status
  end

  test "preview says so plainly when nothing is waiting" do
    sign_in_as(@admin)
    prospective_application(:approved_ready).update_columns(status: ProspectiveApplication::STATUS_PENDING)

    post vc_create_prospectives_preview_path

    assert_response :unprocessable_entity
    assert_match "No approved applications are awaiting account creation.", response.body
  end

  # --- commit --------------------------------------------------------------

  test "commit creates the account and renders the results" do
    sign_in_as(@importer)

    assert_difference "Person.count", 1 do
      post vc_create_prospectives_commit_path
    end

    assert_response :unprocessable_entity
    assert_match "Accounts Created", response.body
    assert_match "prospective account created", response.body

    created = Person.find_by!(callsign: "Sunburst")
    assert_equal Person::PROSPECTIVE, created.status
    assert_equal ProspectiveApplication::STATUS_CREATED,
                 prospective_application(:approved_ready).reload.status
  end

  test "commit never contacts Salesforce while writebacks are off" do
    sign_in_as(@admin)
    fake = FakeSalesforceConnector.new

    with_fake_connector(fake) { post vc_create_prospectives_commit_path }

    assert_response :unprocessable_entity
    assert_empty fake.updates
  end

  # --- failure states ------------------------------------------------------

  test "a Salesforce sign-in failure renders the error callout" do
    sign_in_as(@admin)
    Setting.create!(name: Setting::SF_ENABLE_WRITEBACKS, value: "true")

    # No connector stub: the test database has no SFprd* settings, so the
    # real connector fails auth before any network traffic.
    assert_no_difference "Person.count" do
      post vc_create_prospectives_commit_path
    end

    assert_response :unprocessable_entity
    assert_match "Could Not Sign In to Salesforce", response.body
    assert_match "SFprdAuthUrl", response.body
  end

  test "an application with problems is listed with its reason" do
    sign_in_as(@admin)
    prospective_application(:approved_ready).update_columns(sfuid: "")

    post vc_create_prospectives_preview_path

    assert_response :unprocessable_entity
    assert_match "Missing or Invalid Fields", response.body
    assert_match "SFUID", response.body
  end

  # The preview runs the account's own rules, so a value the account would
  # refuse is listed before anyone presses Create Accounts.
  test "the preview lists an application whose phone the account would refuse" do
    sign_in_as(@admin)
    application = prospective_application(:approved_ready)
    application.update_columns(phone: "775-555-JOAN")

    assert_no_difference %w[Person.count PersonStatus.count] do
      post vc_create_prospectives_preview_path
    end

    assert_response :unprocessable_entity
    assert_select "#group-invalid" do
      assert_select "a", text: "A-#{application.id}"
      assert_select "div", text: I18n.t("errors.messages.phone_invalid", attribute: "Phone")
    end
  end

  # A conflict group names the account involved; without the reason alongside
  # it, a temporary block reads exactly like a permanent one.
  test "a callsign conflict shows why, not just who" do
    sign_in_as(@admin)
    holder = person(:retired_ranger)
    holder.update_columns(status: Person::DECEASED)
    PersonStatus.create!(person_id: holder.id, person_source_id: @admin.id,
                         old_status: Person::RETIRED, new_status: Person::DECEASED,
                         reason: "test", created_at: 2.years.ago)
    prospective_application(:approved_ready).update_columns(approved_handle: holder.callsign)

    post vc_create_prospectives_preview_path

    assert_response :unprocessable_entity
    assert_match "Callsign Conflicts", response.body
    assert_match holder.callsign, response.body
    assert_match "still in the grieving period", response.body
    assert_match "Callsign can be released on", response.body
  end

  test "the commit verdict does not claim nothing was ready when everything failed" do
    sign_in_as(@admin)
    # A failed writeback fails an application that passed every check. A value
    # the account would refuse no longer can: it ends invalid, not ready, and
    # the page would rightly say nothing was ready.
    Setting.create!(name: Setting::SF_ENABLE_WRITEBACKS, value: "true")

    assert_no_difference "Person.count" do
      with_fake_connector(FakeSalesforceConnector.new(update_results: [false])) do
        post vc_create_prospectives_commit_path
      end
    end

    assert_response :unprocessable_entity
    assert_match "Every ready application failed", response.body
    assert_no_match(/No approved applications were ready/, response.body)
  end
end
