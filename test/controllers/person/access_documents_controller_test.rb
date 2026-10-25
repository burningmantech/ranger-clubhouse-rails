# frozen_string_literal: true

require "test_helper"

class Person::AccessDocumentsControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include ActiveSupport::Testing::TimeHelpers
  include TimesheetAdminTestHelper

  setup do
    travel_to Time.zone.local(2026, 4, 16, 12, 0, 0)
    Rails.cache.clear
    Current.reset

    @target = person(:active_ranger)
    @ticketing_admin = person(:echelon_ranger)
    @viewer = person(:ranger_with_custom_gender)

    ensure_role(Role::EDIT_ACCESS_DOCS, "Edit Access Docs")
    ensure_role(Role::EVENT_MANAGEMENT, "Event Management")

    grant_role(@ticketing_admin, Role::EDIT_ACCESS_DOCS)
    grant_role(@viewer, Role::EVENT_MANAGEMENT)

    Current.person = @ticketing_admin
    sign_in_as(@ticketing_admin)
  end

  teardown do
    Current.reset
    travel_back
    Rails.cache.clear
  end

  test "new renders the form" do
    get new_person_access_document_path(@target)

    assert_response :success
    assert_select "body", text: /New Access Document/
  end

  test "create builds the document and logs a create change" do
    assert_difference ["AccessDocument.count", "AccessDocumentChange.count"], 1 do
      post person_access_documents_path(@target), params: {
        access_document: {
          type: AccessDocument::SPT,
          status: AccessDocument::QUALIFIED,
          source_year: 2026,
          expiry_date: "2029",
          delivery_method: AccessDocument::DELIVERY_NONE,
          admission_date: "",
          additional_comments: "Granted per TAS request."
        }
      }
    end

    assert_redirected_to person_tickets_provisions_path(@target)

    document = AccessDocument.order(:id).last
    assert_equal @target.id, document.person_id
    assert_equal Date.new(2029, 9, 15), document.expiry_date
    assert_includes document.comments, "Granted per TAS request."

    change = AccessDocumentChange.order(:id).last
    assert_equal AccessDocumentChange::OP_CREATE, change.operation
    assert_equal document.id, change.record_id
  end

  test "update saves changes, appends a timestamped comment, and logs a modify change" do
    document = access_document(:ar_spt)

    assert_difference "AccessDocumentChange.count", 1 do
      patch person_access_document_path(@target, document), params: {
        access_document: { status: AccessDocument::BANKED, additional_comments: "Verified with TAS." }
      }
    end

    assert_redirected_to person_tickets_provisions_path(@target)

    document.reload
    assert_equal AccessDocument::BANKED, document.status
    assert_includes document.comments, "Verified with TAS."
    assert_includes document.comments, @ticketing_admin.callsign

    change = AccessDocumentChange.order(:id).last
    assert_equal AccessDocumentChange::OP_MODIFY, change.operation
    assert_equal document.id, change.record_id
    assert_includes change.changes.keys, "status"
    refute_includes change.changes.keys, "comments"
  end

  test "admission date maps to any time, a date, or unspecified" do
    document = access_document(:ar_staff_credential)

    patch person_access_document_path(@target, document),
          params: { access_document: { admission_date: "any" } }
    document.reload
    assert document.access_any_time
    assert_nil document.access_date

    patch person_access_document_path(@target, document),
          params: { access_document: { admission_date: "2026-08-20" } }
    document.reload
    refute document.access_any_time
    assert_equal Date.new(2026, 8, 20), document.access_date.to_date

    patch person_access_document_path(@target, document),
          params: { access_document: { admission_date: "" } }
    document.reload
    refute document.access_any_time
    assert_nil document.access_date
  end

  test "destroy removes the document and logs a delete change" do
    document = access_document(:ar_gift)
    document_id = document.id

    assert_difference "AccessDocument.count", -1 do
      delete person_access_document_path(@target, document)
    end

    assert_redirected_to person_tickets_provisions_path(@target)
    assert AccessDocumentChange.where(record_id: document_id,
                                      operation: AccessDocumentChange::OP_DELETE).exists?
  end

  test "history lists recorded changes" do
    document = access_document(:ar_spt)
    patch person_access_document_path(@target, document),
          params: { access_document: { status: AccessDocument::CLAIMED } }

    get history_person_access_document_path(@target, document)

    assert_response :success
    assert_match "Modify", response.body
    assert_match "Status", response.body
    assert_match @ticketing_admin.callsign, response.body
  end

  test "user without the ticketing role cannot update" do
    sign_in_as(@viewer)
    document = access_document(:ar_spt)

    patch person_access_document_path(@target, document),
          params: { access_document: { status: AccessDocument::BANKED } }

    assert_redirected_to me_root_path
    assert_equal AccessDocument::QUALIFIED, document.reload.status
  end
end
