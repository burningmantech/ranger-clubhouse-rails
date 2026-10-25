# frozen_string_literal: true

require "test_helper"

# BMID > Bulk Badge Actions: marking a pasted list of badges as submitted.
#
# There is no bmid fixture file, so the table is cleared and each test builds
# exactly the badges it needs -- the statuses are the whole subject here.
class Ticketing::BulkBmidControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include DomIdTestHelper

  setup do
    Rails.cache.clear
    Current.reset

    @admin = person(:active_ranger)
    @badger = person(:echelon_ranger)
    @outsider = person(:inactive_ranger)
    @target = person(:auditor_ranger)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::EDIT_BMIDS, "Edit BMIDs")
    grant_role(@admin, Role::ADMIN)
    grant_role(@badger, Role::EDIT_BMIDS)

    Bmid.delete_all

    sign_in_as(@admin)
  end

  teardown do
    Current.reset
    Rails.cache.clear
  end

  def preview_params(records, action: "bmidsubmitted", reason: nil)
    { bulk_action: action, records:, reason: }.compact
  end

  def badge(holder, status)
    Bmid.create!(person: holder, year: Current.year, status:)
  end

  # ---------------------------------------------------------------- access

  test "an admin reaches the form" do
    get ticketing_bulk_bmid_path

    assert_response :success
    assert_select "h1", /Bulk Badge Actions/
    assert_unique_dom_ids
  end

  test "someone with the Edit BMIDs role reaches the form" do
    sign_in_as(@badger)

    get ticketing_bulk_bmid_path

    assert_response :success
    assert_select "h1", /Bulk Badge Actions/
  end

  test "someone with neither role is turned away" do
    sign_in_as(@outsider)

    get ticketing_bulk_bmid_path

    assert_redirected_to me_root_path
    assert_equal "Admin or Edit BMIDs role required to change badges in bulk.", flash[:error]
  end

  test "the badge action is offered as a select even though there is only one" do
    get ticketing_bulk_bmid_path

    assert_select "select[name=bulk_action] option[value=bmidsubmitted]",
                  text: "Mark BMID as submitted"
  end

  # --------------------------------------------------------------- preview

  test "preview writes nothing" do
    bmid = badge(@target, Bmid::READY_TO_PRINT)

    assert_no_difference "Bmid.count" do
      post ticketing_preview_bulk_bmid_path, params: preview_params(@target.callsign)
    end

    assert_response :unprocessable_entity
    assert_equal Bmid::READY_TO_PRINT, bmid.reload.status
    assert_select "h1", /Mark BMID as submitted/
    assert_select "tbody tr", 1
    assert_unique_dom_ids
  end

  test "preview marks a badge that is ready to print as a change" do
    badge(@target, Bmid::READY_TO_PRINT)

    post ticketing_preview_bulk_bmid_path, params: preview_params(@target.callsign)

    assert_response :unprocessable_entity
    assert_select "tbody tr td", /Will be applied/
    # Both buttons: there is something to confirm.
    assert_select "input[type=submit]", 2
  end

  test "preview marks a badge flagged with issues as a change" do
    badge(@target, Bmid::ISSUES)

    post ticketing_preview_bulk_bmid_path, params: preview_params(@target.callsign)

    assert_response :unprocessable_entity
    assert_select "tbody tr td", /Will be applied/
    assert_select "input[type=submit]", 2
  end

  test "preview refuses a badge that is still being prepped and names the status" do
    badge(@target, Bmid::IN_PREP)

    post ticketing_preview_bulk_bmid_path, params: preview_params(@target.callsign)

    assert_response :unprocessable_entity
    assert_select "tbody tr td", /Badge status is Prep and cannot be submitted/
    # No confirm button: nothing on the list can be changed.
    assert_select "input[type=submit]", 1
  end

  test "preview refuses a badge marked do not print and names the status" do
    badge(@target, Bmid::DO_NOT_PRINT)

    post ticketing_preview_bulk_bmid_path, params: preview_params(@target.callsign)

    assert_response :unprocessable_entity
    assert_select "tbody tr td", /Badge status is Do Not Print and cannot be submitted/
  end

  # A person with no badge row is in prep by definition, so they draw the same
  # refusal as one that exists at that status -- and no row is invented to say
  # so.
  test "preview treats a person with no badge row as still being prepped" do
    assert_no_difference "Bmid.count" do
      post ticketing_preview_bulk_bmid_path, params: preview_params(@target.callsign)
    end

    assert_response :unprocessable_entity
    assert_select "tbody tr td", /Badge status is Prep and cannot be submitted/
  end

  test "preview reports an already-submitted badge as no change" do
    badge(@target, Bmid::SUBMITTED)

    post ticketing_preview_bulk_bmid_path, params: preview_params(@target.callsign)

    assert_response :unprocessable_entity
    assert_select "tbody tr td", /Already submitted for #{Current.year}/
    assert_select "input[type=submit]", 1
  end

  test "preview marks an unknown callsign as a problem" do
    post ticketing_preview_bulk_bmid_path, params: preview_params("NotARealCallsign")

    assert_response :unprocessable_entity
    assert_select "tbody tr td", /Callsign not found/
    assert_select "input[type=submit]", 1
  end

  test "preview marks a locked account as a problem and never writes to it" do
    locked = person(:deceased_ranger)
    badge(locked, Bmid::READY_TO_PRINT)

    post ticketing_preview_bulk_bmid_path, params: preview_params(locked.callsign)

    assert_response :unprocessable_entity
    assert_select "tbody tr td", /account is locked/i
    assert_select "input[type=submit]", 1
  end

  test "preview refuses a line carrying extra columns" do
    badge(@target, Bmid::READY_TO_PRINT)

    post ticketing_preview_bulk_bmid_path,
         params: preview_params("#{@target.callsign},submitted")

    assert_response :unprocessable_entity
    assert_select "tbody tr td", /takes a callsign only/
  end

  # A spreadsheet export ends every line with a comma; that is still a bare
  # callsign, not a line carrying one blank column.
  test "preview accepts a callsign with a trailing comma" do
    badge(@target, Bmid::READY_TO_PRINT)

    post ticketing_preview_bulk_bmid_path, params: preview_params("#{@target.callsign},")

    assert_response :unprocessable_entity
    assert_select "tbody tr td", /Will be applied/
  end

  test "preview counts a callsign listed twice once" do
    badge(@target, Bmid::READY_TO_PRINT)

    post ticketing_preview_bulk_bmid_path,
         params: preview_params("#{@target.callsign}\n#{@target.callsign}")

    assert_response :unprocessable_entity
    assert_select "tbody tr", 2
    assert_select "tbody tr td", /Listed more than once/
  end

  test "preview re-posts everything the apply needs" do
    badge(@target, Bmid::READY_TO_PRINT)

    post ticketing_preview_bulk_bmid_path,
         params: preview_params(@target.callsign, reason: "print batch 3")

    assert_select "input[name=bulk_action][value=bmidsubmitted]"
    assert_select "input[name=records][value=?]", @target.callsign
    assert_select "input[name=reason][value=?]", "print batch 3"
  end

  test "preview refuses an empty list" do
    post ticketing_preview_bulk_bmid_path, params: preview_params("   \n  ")

    assert_response :unprocessable_entity
    assert_match(/at least one callsign/i, flash[:error])
  end

  test "preview refuses an action the page does not offer" do
    post ticketing_preview_bulk_bmid_path,
         params: preview_params(@target.callsign, action: "sandman_affidavit")

    assert_response :unprocessable_entity
    assert_match(/choose an action/i, flash[:error])
  end

  # ----------------------------------------------------------------- apply

  test "apply submits the badge for the year" do
    bmid = badge(@target, Bmid::READY_TO_PRINT)

    post ticketing_bulk_bmid_path, params: preview_params(@target.callsign)

    assert_response :unprocessable_entity
    assert_equal Bmid::SUBMITTED, bmid.reload.status
    assert_select "[data-controller=scroll-to-top]"
    assert_select "body", /applied to 1 person/
    # The list survives the apply so a correction does not mean re-typing it.
    assert_select "textarea[name=records]", text: @target.callsign
  end

  test "apply submits a badge that was flagged with issues" do
    bmid = badge(@target, Bmid::ISSUES)

    post ticketing_bulk_bmid_path, params: preview_params(@target.callsign)

    assert_equal Bmid::SUBMITTED, bmid.reload.status
  end

  # The one line the page must not quietly invent: a person with no badge is in
  # prep, in prep is refused, so the apply creates nothing for them.
  test "apply creates no badge for a person who has none" do
    assert_no_difference "Bmid.count" do
      post ticketing_bulk_bmid_path, params: preview_params(@target.callsign)
    end

    assert_select "body", /Nothing was changed/
  end

  test "apply leaves a badge it cannot submit alone" do
    bmid = badge(@target, Bmid::DO_NOT_PRINT)

    post ticketing_bulk_bmid_path, params: preview_params(@target.callsign)

    assert_equal Bmid::DO_NOT_PRINT, bmid.reload.status
    assert_select "body", /Nothing was changed/
  end

  test "apply leaves a locked account alone" do
    locked = person(:deceased_ranger)
    bmid = badge(locked, Bmid::READY_TO_PRINT)

    post ticketing_bulk_bmid_path, params: preview_params(locked.callsign)

    assert_equal Bmid::READY_TO_PRINT, bmid.reload.status
    assert_select "body", /Nothing was changed/
  end

  test "apply records the reason and the action in the commit log" do
    badge(@target, Bmid::READY_TO_PRINT)

    post ticketing_bulk_bmid_path,
         params: preview_params(@target.callsign, reason: "print batch 3")

    log = ActionLog.where(event: "bulk-upload").last
    assert_equal "print batch 3", log.data["reason"]
    assert_equal "bmidsubmitted", log.data["action"]
  end

  test "apply logs one commit row naming every result" do
    badge(@target, Bmid::READY_TO_PRINT)

    post ticketing_bulk_bmid_path, params: preview_params(@target.callsign)

    log = ActionLog.where(event: "bulk-upload").last
    assert_equal @target.callsign, log.data["results"].first["callsign"]
    assert_equal "success", log.data["results"].first["status"]
  end

  # ------------------------------------------------------------------ edit

  test "going back to edit keeps the list and the chosen action" do
    post ticketing_edit_bulk_bmid_path,
         params: preview_params(@target.callsign, reason: "print batch 3")

    assert_response :unprocessable_entity
    assert_select "textarea[name=records]", text: @target.callsign
    assert_select "select[name=bulk_action] option[selected][value=bmidsubmitted]"
    assert_select "input[name=reason][value=?]", "print batch 3"
  end
end
