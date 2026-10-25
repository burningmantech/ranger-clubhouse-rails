# frozen_string_literal: true

require "test_helper"

class People::BulkStatusControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include DomIdTestHelper

  setup do
    Rails.cache.clear
    Current.reset

    @admin = person(:active_ranger)
    @outsider = person(:inactive_ranger)
    # Auditor: not a locked status, and moving it to inactive touches nothing but
    # the status history -- the position and role side effects have their own
    # tests upstream of this page.
    @target = person(:auditor_ranger)

    ensure_role(Role::ADMIN, "Admin")
    grant_role(@admin, Role::ADMIN)

    sign_in_as(@admin)
  end

  teardown do
    Current.reset
    Rails.cache.clear
  end

  def preview_params(records, action: Person::INACTIVE, reason: nil)
    { bulk_action: action, records:, reason: }.compact
  end

  # ---------------------------------------------------------------- access

  test "an admin reaches the form" do
    get people_bulk_status_path

    assert_response :success
    assert_select "h1", /Bulk Change Status/
    assert_unique_dom_ids
  end

  test "someone without the admin role is turned away" do
    sign_in_as(@outsider)

    get people_bulk_status_path

    assert_redirected_to me_root_path
    assert_match(/admin role required/i, flash[:error])
  end

  test "all five statuses are offered under one heading" do
    get people_bulk_status_path

    %w[active alpha inactive prospective retired].each do |status|
      assert_select "select[name=bulk_action] optgroup[label=Status] option[value=?]", status
    end
    assert_select "select[name=bulk_action] optgroup[label=Status] option[value=active]",
                  text: "Set as Active"
  end

  test "the vintage flag is offered apart from the statuses" do
    get people_bulk_status_path

    assert_select "select[name=bulk_action] optgroup[label=Flags] option[value=vintage]",
                  text: "Set the Vintage Flag"
  end

  test "the statuses upstream maps but never offers are not offered here" do
    get people_bulk_status_path

    assert_select "select[name=bulk_action] option[value=?]", "past prospective", false
    assert_select "select[name=bulk_action] option[value=?]", "prospective waitlist", false
  end

  # --------------------------------------------------------------- preview

  test "preview writes nothing" do
    assert_no_difference "PersonStatus.count" do
      post people_preview_bulk_status_path, params: preview_params(@target.callsign)
    end

    assert_response :unprocessable_entity
    assert_equal Person::AUDITOR, @target.reload.status
    assert_select "tbody tr", 1
    assert_unique_dom_ids
  end

  test "preview names the move it would make" do
    post people_preview_bulk_status_path, params: preview_params(@target.callsign)

    assert_response :unprocessable_entity
    assert_select "tbody tr td", /auditor → inactive/
  end

  test "preview reports someone already holding the status as no change" do
    post people_preview_bulk_status_path, params: preview_params(@outsider.callsign)

    assert_response :unprocessable_entity
    assert_select "tbody tr td", /Already inactive/
  end

  test "preview reports a callsign already marked vintage as no change" do
    @target.update_columns(vintage: true)

    post people_preview_bulk_status_path,
         params: preview_params(@target.callsign, action: "vintage")

    assert_response :unprocessable_entity
    assert_select "tbody tr td", /Already marked vintage/
  end

  test "preview marks an unknown callsign as a problem" do
    post people_preview_bulk_status_path, params: preview_params("NotARealCallsign")

    assert_response :unprocessable_entity
    assert_select "tbody tr td", /Callsign not found/
    # No confirm button: nothing on the list can be changed.
    assert_select "input[type=submit]", 1
  end

  # The one page that does NOT refuse a locked account. Every other bulk page
  # does, and asserts so in its own suite; here a locked status is the thing
  # being moved, so refusing it would leave no bulk way to reinstate anyone.
  test "preview offers to move a locked account, which is what reinstating one is" do
    locked = person(:deceased_ranger)

    post people_preview_bulk_status_path, params: preview_params(locked.callsign)

    assert_response :unprocessable_entity
    assert_select "tbody tr td", /deceased → inactive/
    assert_select "tbody tr td", { text: /account is locked/i, count: 0 }
    # Two buttons: the confirm as well as the edit, because this list can be applied.
    assert_select "input[type=submit]", 2
    # Still a preview: nothing is written until it is confirmed.
    assert_equal Person::DECEASED, locked.reload.status
  end

  test "preview refuses a line carrying extra columns" do
    post people_preview_bulk_status_path,
         params: preview_params("#{@target.callsign},active")

    assert_response :unprocessable_entity
    assert_select "tbody tr td", /takes a callsign only/
  end

  test "preview counts a callsign listed twice once" do
    post people_preview_bulk_status_path,
         params: preview_params("#{@target.callsign}\n#{@target.callsign}")

    assert_response :unprocessable_entity
    assert_select "tbody tr", 2
    assert_select "tbody tr td", /Listed more than once/
  end

  test "preview spells out what a status change carries with it" do
    post people_preview_bulk_status_path, params: preview_params(@target.callsign)

    assert_select "body", /does more than change the status/
    assert_select "body", /Dirt - Shiny Penny/
  end

  test "preview says something different for the vintage flag" do
    post people_preview_bulk_status_path,
         params: preview_params(@target.callsign, action: "vintage")

    assert_select "body", /can never be released/
    assert_select "body", text: /does more than change the status/, count: 0
  end

  test "preview re-posts everything the apply needs" do
    post people_preview_bulk_status_path,
         params: preview_params(@target.callsign, action: Person::RETIRED,
                                reason: "left the roster in 2024")

    assert_select "input[name=bulk_action][value=?]", Person::RETIRED
    assert_select "input[name=records][value=?]", @target.callsign
    assert_select "input[name=reason][value=?]", "left the roster in 2024"
  end

  test "preview refuses an empty list" do
    post people_preview_bulk_status_path, params: preview_params("   \n  ")

    assert_response :unprocessable_entity
    assert_match(/at least one callsign/i, flash[:error])
  end

  test "preview refuses an action the page does not offer" do
    post people_preview_bulk_status_path,
         params: preview_params(@target.callsign, action: Person::PAST_PROSPECTIVE)

    assert_response :unprocessable_entity
    assert_match(/choose an action/i, flash[:error])
  end

  # ----------------------------------------------------------------- apply

  test "apply changes the status and records the history row" do
    assert_difference "PersonStatus.count", 1 do
      post people_bulk_status_path, params: preview_params(@target.callsign)
    end

    assert_response :unprocessable_entity
    assert_equal Person::INACTIVE, @target.reload.status

    history = PersonStatus.where(person_id: @target.id).last
    assert_equal Person::AUDITOR, history.old_status
    assert_equal Person::INACTIVE, history.new_status
    assert_equal @admin.id, history.person_source_id

    assert_select "[data-controller=scroll-to-top]"
    assert_select "body", /applied to 1 person/
    # The list survives the apply so a correction does not mean re-typing it.
    assert_select "textarea[name=records]", text: @target.callsign
  end

  test "apply records the reason on the history row" do
    post people_bulk_status_path,
         params: preview_params(@target.callsign, reason: "roster cleanup")

    assert_equal "roster cleanup", PersonStatus.where(person_id: @target.id).last.reason
  end

  test "apply sets the vintage flag" do
    post people_bulk_status_path,
         params: preview_params(@target.callsign, action: "vintage")

    assert_response :unprocessable_entity
    assert @target.reload.vintage
    # The flag is not a status: nothing lands in the status history.
    assert_equal Person::AUDITOR, @target.status
    assert_select "body", /applied to 1 person/
  end

  test "apply moves a locked account out of its locked status" do
    locked = person(:deceased_ranger)

    assert_difference "PersonStatus.count", 1 do
      post people_bulk_status_path, params: preview_params(locked.callsign)
    end

    assert_equal Person::INACTIVE, locked.reload.status
    assert_select "body", /applied to 1 person/
  end

  test "apply leaves someone already holding the status alone" do
    assert_no_difference "PersonStatus.count" do
      post people_bulk_status_path, params: preview_params(@outsider.callsign)
    end

    assert_select "body", /Nothing was changed/
  end

  test "apply logs one commit row naming every result" do
    post people_bulk_status_path, params: preview_params(@target.callsign, reason: "roster cleanup")

    log = ActionLog.where(event: "bulk-upload").last
    assert_equal Person::INACTIVE, log.data["action"]
    assert_equal "roster cleanup", log.data["reason"]
    assert_equal @target.callsign, log.data["results"].first["callsign"]
    assert_equal "success", log.data["results"].first["status"]
  end

  # ------------------------------------------------------------------ edit

  test "going back to edit keeps the list and the chosen action" do
    post people_edit_bulk_status_path,
         params: preview_params(@target.callsign, action: Person::RETIRED,
                                reason: "left the roster in 2024")

    assert_response :unprocessable_entity
    assert_select "textarea[name=records]", text: @target.callsign
    assert_select "select[name=bulk_action] option[selected][value=?]", Person::RETIRED
    assert_select "input[name=reason][value=?]", "left the roster in 2024"
  end
end
