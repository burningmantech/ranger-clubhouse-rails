# frozen_string_literal: true

require "test_helper"

class Vehicles::BulkPaperworkControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include DomIdTestHelper

  setup do
    Rails.cache.clear
    Current.reset

    @admin = person(:active_ranger)
    @vehicle_manager = person(:retired_ranger)
    @outsider = person(:inactive_ranger)
    @target = person(:auditor_ranger)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::VEHICLE_MANAGEMENT, "Vehicle Management")
    grant_role(@admin, Role::ADMIN)
    grant_role(@vehicle_manager, Role::VEHICLE_MANAGEMENT)

    sign_in_as(@admin)
  end

  teardown do
    Current.reset
    Rails.cache.clear
  end

  def preview_params(records, action: "signed_motorpool_agreement", reason: nil)
    { bulk_action: action, records:, reason: }.compact
  end

  # ---------------------------------------------------------------- access

  test "an admin reaches the form" do
    get vehicles_bulk_paperwork_path

    assert_response :success
    assert_select "h1", /Bulk Record Vehicle Paperwork/
    assert_unique_dom_ids
  end

  test "a vehicle manager reaches the form" do
    sign_in_as(@vehicle_manager)

    get vehicles_bulk_paperwork_path

    assert_response :success
  end

  test "someone with neither role is turned away" do
    sign_in_as(@outsider)

    get vehicles_bulk_paperwork_path

    assert_redirected_to me_root_path
    assert_match(/vehicle management/i, flash[:error])
  end

  test "all four paperwork flags are offered" do
    get vehicles_bulk_paperwork_path

    %w[signed_motorpool_agreement org_vehicle_insurance mvr_eligible may_request_stickers].each do |id|
      assert_select "select[name=bulk_action] option[value=?]", id
    end
  end

  test "the read-only audit is linked from the form" do
    get vehicles_bulk_paperwork_path

    assert_select "a[href=?]", vehicles_paperwork_path
  end

  # --------------------------------------------------------------- preview

  test "preview writes nothing" do
    assert_no_difference "PersonEvent.count" do
      post vehicles_preview_bulk_paperwork_path, params: preview_params(@target.callsign)
    end

    assert_response :unprocessable_entity
    assert_select "tbody tr", 1
    assert_unique_dom_ids
  end

  # ----------------------------------------------------------------- apply

  test "apply records each flag on the person's event year" do
    %w[signed_motorpool_agreement org_vehicle_insurance mvr_eligible may_request_stickers].each do |flag|
      post vehicles_bulk_paperwork_path, params: preview_params(@target.callsign, action: flag)

      assert_response :unprocessable_entity
      assert PersonEvent.find_for_person_year(@target.id, Current.year).public_send(flag),
             "#{flag} should be recorded"
    end
  end

  test "apply creates the event row for someone who has none" do
    assert_nil PersonEvent.find_for_person_year(@target.id, Current.year)

    post vehicles_bulk_paperwork_path, params: preview_params(@target.callsign)

    assert PersonEvent.find_for_person_year(@target.id, Current.year).signed_motorpool_agreement
  end

  test "a flag already recorded reads as no change and the banner stays amber" do
    PersonEvent.create!(person_id: @target.id, year: Current.year, signed_motorpool_agreement: true)

    post vehicles_bulk_paperwork_path, params: preview_params(@target.callsign)

    assert_select "body", /Nothing was changed/
  end

  test "one year's paperwork does not touch another year's row" do
    PersonEvent.create!(person_id: @target.id, year: Current.year - 1)

    post vehicles_bulk_paperwork_path, params: preview_params(@target.callsign)

    assert_not PersonEvent.find_for_person_year(@target.id, Current.year - 1).signed_motorpool_agreement
    assert PersonEvent.find_for_person_year(@target.id, Current.year).signed_motorpool_agreement
  end

  # ------------------------------------------------------------------ edit

  test "going back to edit keeps the list and the chosen action" do
    post vehicles_edit_bulk_paperwork_path,
         params: preview_params(@target.callsign, action: "mvr_eligible", reason: "MVR batch")

    assert_response :unprocessable_entity
    assert_select "textarea[name=records]", text: @target.callsign
    assert_select "select[name=bulk_action] option[selected][value=mvr_eligible]"
    assert_select "input[name=reason][value=?]", "MVR batch"
  end

  # ------------------------------------------------------------------ audit

  # person_event keeps no history of its own, so this row is the whole trail --
  # which is why it names every line, not only the ones that wrote.
  test "the commit log names the lines that could not be used, not just the successes" do
    post vehicles_bulk_paperwork_path,
         params: preview_params("#{@target.callsign}\nnosuchcallsign", reason: "signed at the gate")

    log = ActionLog.where(event: "bulk-upload").last
    results = log.data["results"]

    assert_equal 2, results.size, "every line is reported, not just the ones that wrote"
    assert_equal "success", results.find { |r| r["callsign"] == @target.callsign }["status"]

    refused = results.find { |r| r["callsign"] == "nosuchcallsign" }
    assert_equal "not_found", refused["status"]
    assert_match(/not found/i, refused["details"])
    assert_equal "signed at the gate", log.data["reason"]
  end

  # The banner is amber, not green, when nothing was written: a run where every
  # line was unusable wrote nothing, and green invites a reader scanning by
  # colour to move on from a job that did not happen.
  test "a run that changed nothing does not paint the banner green" do
    post vehicles_bulk_paperwork_path, params: preview_params("nosuchcallsign")

    assert_select "body", /Nothing was changed/
    assert_select ".alert-success", 0
  end
end
