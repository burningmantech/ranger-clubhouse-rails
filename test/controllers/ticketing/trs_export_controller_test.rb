# frozen_string_literal: true

require "test_helper"

# Ticketing > TRS Export: the filtered selection table, the export POST (audit
# comments plus the data: URI CSV), and the mark-submitted POST. The export
# rules themselves live in test/lib/trs_export_test.rb.
#
# The page reads the whole access_document table and the shared fixtures
# belong to other suites, so every test starts from an empty one and builds
# exactly the documents it needs.
class Ticketing::TrsExportControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include BulkSelectTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include DomIdTestHelper # assert_unique_dom_ids
  include ActiveSupport::Testing::TimeHelpers

  YEAR = 2026

  setup do
    travel_to Time.zone.local(YEAR, 7, 1, 12, 0, 0)
    Rails.cache.clear
    Current.reset

    @admin = person(:active_ranger)
    @outsider = person(:inactive_ranger)
    @holder = person(:ranger_with_custom_gender)

    ensure_role(Role::ADMIN, "Admin")
    grant_role(@admin, Role::ADMIN)

    AccessDocument.delete_all

    sign_in_as(@admin)
  end

  teardown do
    Current.reset
    Rails.cache.clear
    travel_back
  end

  def document(person, type, status: AccessDocument::CLAIMED, **attributes)
    AccessDocument.create!(
      person:,
      type:,
      status:,
      source_year: YEAR,
      delivery_method: AccessDocument::DELIVERY_NONE,
      **attributes
    )
  end

  test "the page is refused without the admin or edit access documents role" do
    sign_in_as(@outsider)

    get ticketing_trs_export_path

    assert_redirected_to me_root_path
    assert_equal "Admin or Edit Access Documents role required to export to TRS.", flash[:error]
  end

  test "the default All view lists everything read-only" do
    document(@holder, AccessDocument::GIFT, delivery_method: AccessDocument::DELIVERY_POSTAL)

    get ticketing_trs_export_path

    assert_response :success
    assert_match "read-only overview", response.body
    assert_select "input[name='ids[]']", 0
    assert_select "a[href=?]", person_tickets_provisions_path(@holder), text: @holder.callsign
  end

  test "a type filter renders checkboxes and flags problem documents" do
    fine = document(@holder, AccessDocument::SAP, access_any_time: true)
    dateless = document(@holder, AccessDocument::SAP)

    get ticketing_trs_export_path(filter: "work_access_pass_ranger")

    assert_response :success
    assert_select "input[name='ids[]'][value=?]", fine.id.to_s
    assert_select "input[name='ids[]'][value=?][data-skip-select-all]", dateless.id.to_s
    assert_match "missing access date", response.body
  end

  test "the export form carries the filter without colliding with the filter select" do
    document(@holder, AccessDocument::SAP, access_any_time: true)

    get ticketing_trs_export_path(filter: "work_access_pass_ranger")

    assert_response :success
    assert_select "select#filter", 1
    assert_select "input[type=hidden][name=filter][value=?]", "work_access_pass_ranger"
    assert_unique_dom_ids
  end

  test "a combined filter posts both document ids in one checkbox" do
    sc = document(@holder, AccessDocument::STAFF_CREDENTIAL, access_any_time: true)
    vp = document(@holder, AccessDocument::VEHICLE_PASS_GIFT)

    get ticketing_trs_export_path(filter: "staff_credential_vp")

    assert_response :success
    assert_select "input[name='ids[]'][value=?]", "#{sc.id},#{vp.id}"
  end

  test "export stamps the comment and embeds the CSV download" do
    sc = document(@holder, AccessDocument::STAFF_CREDENTIAL, access_date: Time.zone.local(YEAR, 8, 14, 12, 0, 0))
    banked = document(@holder, AccessDocument::GIFT, status: AccessDocument::BANKED)

    post ticketing_trs_export_export_path, params: { filter: "staff_credential", ids: [sc.id.to_s, banked.id.to_s] }

    assert_response :unprocessable_entity
    assert_select "[data-controller=scroll-to-top]"
    assert_match "#{@admin.callsign}: exported with filter staff_credential", sc.reload.comments
    assert_match "data:text/csv;charset=utf-8,", response.body
    assert_match "trs-staff-credential-", response.body
    assert_match "RAD-#{banked.id} &mdash; status is now banked", response.body
    # The CSV rides in the page as a URL-encoded data: URI.
    assert_match ERB::Util.url_encode("CRED Fri 08/14 - RAD-#{sc.id} exported by CHID ##{@admin.id}"), response.body
    # The results table starts with every row ticked, and its count says so.
    assert_select "[data-checkbox-select-all-target=checkbox][checked]"
    assert_bulk_select_count_matches_ticked
  end

  test "mark submitted flips only the posted claimed documents" do
    spt = document(@holder, AccessDocument::SPT, delivery_method: AccessDocument::DELIVERY_WILL_CALL)
    unchecked = document(@holder, AccessDocument::SPT, delivery_method: AccessDocument::DELIVERY_WILL_CALL)

    post ticketing_trs_export_mark_submitted_path,
         params: { filter: "special_price_ticket", ids: [spt.id.to_s] }

    assert_response :unprocessable_entity
    assert_select "[data-controller=scroll-to-top]"
    assert_equal AccessDocument::SUBMITTED, spt.reload.status
    assert_match "bulk marked submitted\ndelivery will_call", spt.comments
    assert_equal AccessDocument::CLAIMED, unchecked.reload.status
    assert_match "RAD-#{spt.id}", response.body
  end

  test "posting the all filter or no filter is refused" do
    doc = document(@holder, AccessDocument::GIFT)

    post ticketing_trs_export_export_path, params: { filter: "all", ids: [doc.id.to_s] }

    assert_redirected_to ticketing_trs_export_path
    assert_equal "Pick a specific filter before exporting.", flash[:alert]
    assert_no_match(/exported with filter/, doc.reload.comments.to_s)
  end

  test "posting no ids is refused" do
    post ticketing_trs_export_export_path, params: { filter: "gift_ticket" }

    assert_redirected_to ticketing_trs_export_path(filter: "gift_ticket")
    assert_equal "Select at least one item.", flash[:alert]
  end

  # Integer() kept "0" and read " #{id}", space and all, as the id, which
  # marked that document submitted.
  test "posting ids that are not ids is refused as no selection" do
    spt = document(@holder, AccessDocument::SPT, delivery_method: AccessDocument::DELIVERY_WILL_CALL)

    post ticketing_trs_export_mark_submitted_path,
         params: { filter: "special_price_ticket", ids: ["", "0", " #{spt.id}"] }

    assert_redirected_to ticketing_trs_export_path(filter: "special_price_ticket")
    assert_equal "Select at least one item.", flash[:alert]
    assert_equal AccessDocument::CLAIMED, spt.reload.status
  end

  test "posting more ids than the batch limit is refused before any writes" do
    ids = (1..(TrsExport::MAX_BATCH_SIZE + 1)).map(&:to_s)

    post ticketing_trs_export_export_path, params: { filter: "gift_ticket", ids: ids }

    assert_redirected_to ticketing_trs_export_path(filter: "gift_ticket")
    assert_match(/exceeds the TRS batch limit/, flash[:alert])
  end

  test "an export where nothing is still claimed redirects with an alert" do
    banked = document(@holder, AccessDocument::GIFT, status: AccessDocument::BANKED)

    post ticketing_trs_export_export_path, params: { filter: "gift_ticket", ids: [banked.id.to_s] }

    assert_redirected_to ticketing_trs_export_path(filter: "gift_ticket")
    assert_equal "None of the selected items are still exportable. Nothing was written.", flash[:alert]
  end
end
