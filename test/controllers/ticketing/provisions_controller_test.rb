# frozen_string_literal: true

require "test_helper"

# Ticketing > Provisions: the flat current-provision list with its type, status,
# and allocation filters, its CSV export, and the edit/delete round trip that
# returns to the filtered list.
#
# The action reads the whole provision table and the shared fixtures belong to
# other suites, so every test starts from an empty table and builds exactly the
# provisions it needs.
class Ticketing::ProvisionsControllerTest < ActionDispatch::IntegrationTest
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

    Provision.delete_all

    sign_in_as(@admin)
  end

  teardown do
    Current.reset
    Rails.cache.clear
    travel_back
  end

  # --- who may look --------------------------------------------------------

  test "the list renders for an admin" do
    radio = provision_for(@admin, type: Provision::EVENT_RADIO, item_count: 2)

    get ticketing_provisions_path

    assert_response :success
    assert_equal [radio.display_ref], rendered_refs
    assert_select "a[href=?]", person_path(@admin), text: @admin.callsign
    assert_match "Showing 1 of 1 provision", response.body
  end

  test "the list renders with only the edit access documents role" do
    sign_in_as(@ticketing)
    shower = provision_for(@ticketing)

    get ticketing_provisions_path

    assert_response :success
    assert_equal [shower.display_ref], rendered_refs
  end

  test "the list is refused without the admin or edit access documents role" do
    sign_in_as(@outsider)

    get ticketing_provisions_path

    assert_redirected_to me_root_path
    assert_equal "Admin or Edit Access Documents role required to administer provisions.", flash[:error]
  end

  test "editing is refused without the admin or edit access documents role" do
    provision = provision_for(@admin)
    sign_in_as(@outsider)

    get edit_ticketing_provision_path(provision)

    assert_redirected_to me_root_path
    assert_equal "Admin or Edit Access Documents role required to administer provisions.", flash[:error]
  end

  # --- filters --------------------------------------------------------------

  test "the type filter narrows the list to that type" do
    meals = provision_for(@admin, type: Provision::MEALS)
    shower = provision_for(@admin)
    provision_for(@admin, type: Provision::EVENT_RADIO, item_count: 1)

    get ticketing_provisions_path(type: Provision::MEALS)

    assert_response :success
    assert_equal [meals.display_ref], rendered_refs
    assert_not_includes rendered_refs, shower.display_ref
    # Y stays the whole current set so the filters visibly narrow X against it.
    assert_match "Showing 1 of 3 provisions", response.body
  end

  test "the status filter narrows the list to that status" do
    available = provision_for(@admin)
    banked = provision_for(@admin, status: Provision::BANKED)

    get ticketing_provisions_path(status: Provision::BANKED)

    assert_response :success
    assert_equal [banked.display_ref], rendered_refs
    assert_not_includes rendered_refs, available.display_ref
    assert_match "Showing 1 of 2 provisions", response.body
  end

  test "the allocated filter narrows the list either way" do
    earned = provision_for(@admin)
    allocated = provision_for(@admin, type: Provision::MEALS, is_allocated: true)

    get ticketing_provisions_path(allocated: "1")

    assert_response :success
    assert_equal [allocated.display_ref], rendered_refs

    get ticketing_provisions_path(allocated: "0")

    assert_response :success
    assert_equal [earned.display_ref], rendered_refs
  end

  test "the type and allocated filters narrow together" do
    provision_for(@admin, type: Provision::MEALS)
    provision_for(@admin, is_allocated: true)
    wanted = provision_for(@admin, type: Provision::MEALS, is_allocated: true)

    get ticketing_provisions_path(type: Provision::MEALS, allocated: "1")

    assert_response :success
    assert_equal [wanted.display_ref], rendered_refs
  end

  # A hand-edited URL must not be able to empty the page or park a bogus label
  # in the filter bar, so an unknown value falls back to showing everything.
  test "an unknown type, status, or allocation falls back to no filter" do
    meals = provision_for(@admin, type: Provision::MEALS)
    shower = provision_for(@admin)

    get ticketing_provisions_path(type: "bogus", status: "bogus", allocated: "bogus")

    assert_response :success
    assert_equal [meals.display_ref, shower.display_ref].sort, rendered_refs.sort
    assert_match "Showing 2 of 2 provisions", response.body
  end

  test "the default view keeps every current status and drops the spent ones" do
    current = Provision::CURRENT_STATUSES.to_h { |status| [status, provision_for(@admin, status:)] }
    spent = Provision::INVALID_STATUSES.to_h { |status| [status, provision_for(@admin, status:)] }

    get ticketing_provisions_path

    assert_response :success

    refs = rendered_refs
    current.each do |status, provision|
      assert_includes refs, provision.display_ref, "#{status} should be listed by default"
    end
    spent.each do |status, provision|
      assert_not_includes refs, provision.display_ref, "#{status} should not be listed by default"
    end

    assert_equal 4, refs.size
    assert_match "Showing 4 of 4 provisions", response.body
  end

  # --- CSV export -----------------------------------------------------------

  test "the csv export returns the filtered rows under the expected filename" do
    radio = provision_for(@admin, type: Provision::EVENT_RADIO, item_count: 3)
    shower = provision_for(@admin)

    get ticketing_provisions_path(format: :csv, type: Provision::EVENT_RADIO)

    assert_response :success
    assert_equal "text/csv", response.media_type
    assert_match %(filename="#{YEAR}-current-provisions.csv"), response.headers["Content-Disposition"]

    lines = response.body.split("\n")
    assert_equal "Provision ID,Person,Type,Status,Item Count,Allocated?,Source Year", lines.first
    assert_equal 2, lines.size, "only the filtered row belongs in the export"
    assert_equal "#{radio.display_ref},#{@admin.callsign},Event Radio,available,3,No,#{YEAR}", lines.second
    assert_not_includes response.body, shower.display_ref
  end

  # A shower pass has no count and the spreadsheet should say so with a blank
  # cell, not with the table's dash placeholder.
  test "the csv export leaves the item count blank when there is none" do
    allocated = provision_for(@admin, is_allocated: true)

    get ticketing_provisions_path(format: :csv)

    assert_response :success
    assert_equal "#{allocated.display_ref},#{@admin.callsign},Wet Spot Access,available,,Yes,#{YEAR}",
                 response.body.split("\n").second
  end

  # --- edit, update, delete -------------------------------------------------

  test "the id links to the edit page carrying the active filters" do
    provision = provision_for(@admin, type: Provision::MEALS)

    get ticketing_provisions_path(type: Provision::MEALS)

    assert_response :success
    assert_select "a[href=?]", edit_ticketing_provision_path(provision, type: Provision::MEALS),
                  text: provision.display_ref
  end

  test "edit renders the shared provision form" do
    provision = provision_for(@admin, type: Provision::EVENT_RADIO, item_count: 1)

    get edit_ticketing_provision_path(provision)

    assert_response :success
    assert_match provision.display_ref, response.body
    assert_match @admin.callsign, response.body
    assert_select "form[action=?]", ticketing_provision_path(provision)
  end

  test "update saves the change and returns to the filtered list" do
    provision = provision_for(@admin)

    patch ticketing_provision_path(provision, status: Provision::BANKED), params: {
      provision: { status: Provision::CLAIMED, additional_comments: "Issued at HQ." }
    }

    assert_redirected_to ticketing_provisions_path(status: Provision::BANKED)

    provision.reload
    assert_equal Provision::CLAIMED, provision.status
    assert_includes provision.comments, "Issued at HQ."
  end

  test "update re-renders the form when the record is invalid" do
    provision = provision_for(@admin, type: Provision::MEALS, is_allocated: true)

    patch ticketing_provision_path(provision), params: {
      provision: { status: Provision::BANKED }
    }

    assert_response :unprocessable_entity
    assert_match "cannot be banked", response.body
    assert_equal Provision::AVAILABLE, provision.reload.status
  end

  test "destroy removes the provision and returns to the filtered list" do
    provision = provision_for(@admin)

    assert_difference "Provision.count", -1 do
      delete ticketing_provision_path(provision, type: Provision::WET_SPOT)
    end

    assert_redirected_to ticketing_provisions_path(type: Provision::WET_SPOT)
  end

  private

  # A wet spot pass by default: it needs no count and no meal periods, so it is
  # the least noisy stand-in when the test is about something else.
  def provision_for(holder, type: Provision::WET_SPOT, status: Provision::AVAILABLE, **attributes)
    attributes[:event_week_meals] = true if type == Provision::MEALS

    Provision.create!(person: holder, type:, status:, source_year: YEAR,
                      expires_on: YEAR + 3, **attributes)
  end

  # The RP reference heading each rendered row of the table.
  def rendered_refs
    css_select("tbody th").map { |cell| cell.text.strip }
  end
end
