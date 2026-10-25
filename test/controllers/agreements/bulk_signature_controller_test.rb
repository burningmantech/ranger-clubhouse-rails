# frozen_string_literal: true

require "test_helper"

class Agreements::BulkSignatureControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include DomIdTestHelper

  setup do
    Rails.cache.clear
    Current.reset

    @admin = person(:active_ranger)
    @outsider = person(:inactive_ranger)
    @target = person(:auditor_ranger)

    ensure_role(Role::ADMIN, "Admin")
    grant_role(@admin, Role::ADMIN)

    sign_in_as(@admin)
  end

  teardown do
    Current.reset
    Rails.cache.clear
  end

  def preview_params(records, action: "sandman_affidavit", reason: nil)
    { bulk_action: action, records:, reason: }.compact
  end

  # ---------------------------------------------------------------- access

  test "an admin reaches the form" do
    get agreements_bulk_signature_path

    assert_response :success
    assert_select "h1", /Bulk Record a Signed Agreement/
    assert_unique_dom_ids
  end

  test "someone without the admin role is turned away" do
    sign_in_as(@outsider)

    get agreements_bulk_signature_path

    assert_redirected_to me_root_path
    assert_match(/admin role required/i, flash[:error])
  end

  test "the agreement is offered as a select even though there is only one" do
    get agreements_bulk_signature_path

    assert_select "select[name=bulk_action] option[value=sandman_affidavit]",
                  text: "Signed Sandman Affidavit"
  end

  # --------------------------------------------------------------- preview

  test "preview writes nothing" do
    assert_no_difference "PersonEvent.count" do
      post agreements_preview_bulk_signature_path, params: preview_params(@target.callsign)
    end

    assert_response :unprocessable_entity
    assert_select "h1", /Signed Sandman Affidavit/
    assert_select "tbody tr", 1
    assert_unique_dom_ids
  end

  test "preview marks an unknown callsign as a problem" do
    post agreements_preview_bulk_signature_path, params: preview_params("NotARealCallsign")

    assert_response :unprocessable_entity
    assert_select "tbody tr td", /Callsign not found/
    # No confirm button: nothing on the list can be changed.
    assert_select "input[type=submit]", 1
  end

  test "preview marks a locked account as a problem and never writes to it" do
    locked = person(:deceased_ranger)

    post agreements_preview_bulk_signature_path, params: preview_params(locked.callsign)

    assert_response :unprocessable_entity
    assert_select "tbody tr td", /account is locked/i
    assert_select "input[type=submit]", 1
  end

  test "preview reports an already-recorded agreement as no change" do
    PersonEvent.create!(person_id: @target.id, year: Current.year, sandman_affidavit: true)

    post agreements_preview_bulk_signature_path, params: preview_params(@target.callsign)

    assert_response :unprocessable_entity
    assert_select "tbody tr td", /Already recorded/
  end

  test "preview refuses a line carrying extra columns" do
    post agreements_preview_bulk_signature_path,
         params: preview_params("#{@target.callsign},2026-01-01")

    assert_response :unprocessable_entity
    assert_select "tbody tr td", /takes a callsign only/
  end

  test "preview counts a callsign listed twice once" do
    post agreements_preview_bulk_signature_path,
         params: preview_params("#{@target.callsign}\n#{@target.callsign}")

    assert_response :unprocessable_entity
    assert_select "tbody tr", 2
    assert_select "tbody tr td", /Listed more than once/
  end

  test "preview re-posts everything the apply needs" do
    post agreements_preview_bulk_signature_path,
         params: preview_params(@target.callsign, reason: "signed at training")

    assert_select "input[name=bulk_action][value=sandman_affidavit]"
    assert_select "input[name=records][value=?]", @target.callsign
    assert_select "input[name=reason][value=?]", "signed at training"
  end

  test "preview refuses an empty list" do
    post agreements_preview_bulk_signature_path, params: preview_params("   \n  ")

    assert_response :unprocessable_entity
    assert_match(/at least one callsign/i, flash[:error])
  end

  test "preview refuses an action the page does not offer" do
    post agreements_preview_bulk_signature_path,
         params: preview_params(@target.callsign, action: "mvr_eligible")

    assert_response :unprocessable_entity
    assert_match(/choose an action/i, flash[:error])
  end

  # ----------------------------------------------------------------- apply

  test "apply records the agreement for the year" do
    post agreements_bulk_signature_path, params: preview_params(@target.callsign)

    assert_response :unprocessable_entity
    assert PersonEvent.find_for_person_year(@target.id, Current.year).sandman_affidavit
    assert_select "[data-controller=scroll-to-top]"
    assert_select "body", /applied to 1 person/
    # The list survives the apply so a correction does not mean re-typing it.
    assert_select "textarea[name=records]", text: @target.callsign
  end

  test "apply leaves a locked account alone" do
    locked = person(:deceased_ranger)

    post agreements_bulk_signature_path, params: preview_params(locked.callsign)

    assert_nil PersonEvent.find_for_person_year(locked.id, Current.year)
    assert_select "body", /Nothing was changed/
  end

  test "apply records the reason in the person event history" do
    post agreements_bulk_signature_path,
         params: preview_params(@target.callsign, reason: "signed at training")

    log = ActionLog.where(event: "bulk-upload").last
    assert_equal "signed at training", log.data["reason"]
    assert_equal "sandman_affidavit", log.data["action"]
  end

  test "apply logs one commit row naming every result" do
    post agreements_bulk_signature_path, params: preview_params(@target.callsign)

    log = ActionLog.where(event: "bulk-upload").last
    assert_equal @target.callsign, log.data["results"].first["callsign"]
    assert_equal "success", log.data["results"].first["status"]
  end

  # ------------------------------------------------------------------ edit

  test "going back to edit keeps the list and the chosen action" do
    post agreements_edit_bulk_signature_path,
         params: preview_params(@target.callsign, reason: "signed at training")

    assert_response :unprocessable_entity
    assert_select "textarea[name=records]", text: @target.callsign
    assert_select "select[name=bulk_action] option[selected][value=sandman_affidavit]"
    assert_select "input[name=reason][value=?]", "signed at training"
  end

  # ------------------------------------------------------------------ audit

  # The write goes through Agreements.admin_set_signature rather than setting
  # the person_event column by hand, so a bulk-recorded signature lands in the
  # same agreement history a signature recorded one person at a time does.
  # person_event keeps no history of its own, so without this there was none.
  test "apply writes the agreement signature history row" do
    post agreements_bulk_signature_path, params: preview_params(@target.callsign)

    row = ActionLog.where(target_person_id: @target.id, event: "agreement-signature").last
    assert_not_nil row, "a bulk signature must appear in the agreement history"
    assert_equal Document::SANDMAN_AFFIDAVIT_TAG, row.data["tag"]
    assert row.data["signature"]
    assert person_event_for(@target).sandman_affidavit
  end

  def person_event_for(person) = PersonEvent.find_by(person_id: person.id, year: Current.year)
end
