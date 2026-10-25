# frozen_string_literal: true

require "test_helper"

class Ticketing::BulkAccessDocumentsControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include DomIdTestHelper

  setup do
    Rails.cache.clear
    Current.reset

    @admin = person(:active_ranger)
    @outsider = person(:inactive_ranger)
    # Holds no access documents of its own, so every count below is about the
    # documents a test made.
    @target = person(:auditor_ranger)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::EDIT_ACCESS_DOCS, "Edit Access Documents")
    grant_role(@admin, Role::ADMIN)

    sign_in_as(@admin)
  end

  teardown do
    Current.reset
    Rails.cache.clear
  end

  def preview_params(records, action: "tickets", reason: nil)
    { bulk_action: action, records:, reason: }.compact
  end

  # The years a line inherits when it names none. Read from the handler rather
  # than written out: they turn over in September, and a test that hard-coded
  # them would start failing on a date that has nothing to do with the code.
  def default_years = BulkUpload::TicketHandler.default_years

  def documents_for(person) = AccessDocument.where(person_id: person.id).order(:id)

  def create_document(person, type, **attributes)
    AccessDocument.create!(person_id: person.id, type:, status: AccessDocument::QUALIFIED,
                           delivery_method: AccessDocument::DELIVERY_NONE,
                           source_year: Current.year, **attributes)
  end

  # ---------------------------------------------------------------- access

  test "an admin reaches the form" do
    get ticketing_bulk_access_documents_path

    assert_response :success
    assert_select "h1", /Bulk Access Documents/
    assert_unique_dom_ids
  end

  test "the ticketing role reaches the form without being an admin" do
    grant_role(@target, Role::EDIT_ACCESS_DOCS)
    sign_in_as(@target)

    get ticketing_bulk_access_documents_path

    assert_response :success
  end

  test "someone with neither role is turned away" do
    sign_in_as(@outsider)

    get ticketing_bulk_access_documents_path

    assert_redirected_to me_root_path
    assert_match(/edit access documents role required/i, flash[:error])
  end

  test "both actions are offered, under upstream's ids" do
    get ticketing_bulk_access_documents_path

    assert_select "select[name=bulk_action] option[value=tickets]", text: "Create Access Documents"
    assert_select "select[name=bulk_action] option[value=wap]", text: "Update SAP dates"
  end

  test "the form spells out both line formats and this year's defaults" do
    source_year, expiry_year = default_years

    get ticketing_bulk_access_documents_path

    assert_select "code", text: "VPGIFT"
    assert_select "body", /source year #{source_year} and expiry year #{expiry_year}/
    assert_select "body", /#{Current.year}-08-05/
  end

  # ------------------------------------------------------- tickets: preview

  test "preview writes nothing" do
    assert_no_difference "AccessDocument.count" do
      post ticketing_preview_bulk_access_documents_path,
           params: preview_params("#{@target.callsign},SPT")
    end

    assert_response :unprocessable_entity
    assert_select "tbody tr", 1
    assert_unique_dom_ids
  end

  test "preview names the years a line did not mention" do
    source_year, expiry_year = default_years

    post ticketing_preview_bulk_access_documents_path,
         params: preview_params("#{@target.callsign},SPT")

    assert_select "tbody tr td", /Special Price Ticket, source year #{source_year}, expires #{expiry_year}/
  end

  test "preview marks a second document of the same type as a replacement" do
    create_document(@target, AccessDocument::SPT)

    post ticketing_preview_bulk_access_documents_path,
         params: preview_params("#{@target.callsign},SPT")

    assert_select "tbody tr td", /this adds another/
    assert_select "tbody tr td", /Will replace/
  end

  test "preview refuses a line with no ticket type" do
    post ticketing_preview_bulk_access_documents_path, params: preview_params(@target.callsign)

    assert_select "tbody tr td", /missing ticket type/
  end

  test "preview refuses an unknown ticket type" do
    post ticketing_preview_bulk_access_documents_path,
         params: preview_params("#{@target.callsign},NOPE")

    assert_select "tbody tr td", /Unknown ticket type \[NOPE\]/
  end

  test "preview refuses an unparseable access date" do
    post ticketing_preview_bulk_access_documents_path,
         params: preview_params("#{@target.callsign},CRED,not-a-date")

    assert_select "tbody tr td", /Access date is invalid/
  end

  # The guard that earns its keep: "2026" is a year, but a date parser reads it
  # as a time of day and would take it for today.
  test "preview refuses a bare year in the access date column" do
    post ticketing_preview_bulk_access_documents_path,
         params: preview_params("#{@target.callsign},CRED,#{Current.year}")

    assert_select "tbody tr td", /Access date is invalid.+\[#{Current.year}\]/
  end

  test "preview refuses an access date from a previous year" do
    post ticketing_preview_bulk_access_documents_path,
         params: preview_params("#{@target.callsign},CRED,#{Current.year - 1}-08-10")

    assert_select "tbody tr td", /Access date is before this year #{Current.year}/
  end

  test "preview refuses a column the type does not take" do
    post ticketing_preview_bulk_access_documents_path,
         params: preview_params("#{@target.callsign},VP,#{Current.year}-08-10")

    assert_select "tbody tr td", /Unexpected additional data for Vehicle Pass \(Special Price\)/
  end

  test "preview refuses a source year in the future" do
    post ticketing_preview_bulk_access_documents_path,
         params: preview_params("#{@target.callsign},SPT,#{Current.year + 1}")

    assert_select "tbody tr td", /Source Year is in the future/
  end

  test "preview refuses a source year that is not a number" do
    post ticketing_preview_bulk_access_documents_path,
         params: preview_params("#{@target.callsign},SPT,soon")

    assert_select "tbody tr td", /Source Year is not a number/
  end

  test "preview refuses an expiry year before the source year" do
    post ticketing_preview_bulk_access_documents_path,
         params: preview_params("#{@target.callsign},SPT,#{Current.year},#{Current.year - 1}")

    assert_select "tbody tr td",
                  /Source year \[#{Current.year}\] must not be after expiry year \[#{Current.year - 1}\]/
  end

  test "preview refuses a locked account before the line is even read" do
    locked = person(:deceased_ranger)

    post ticketing_preview_bulk_access_documents_path,
         params: preview_params("#{locked.callsign},SPT")

    assert_select "tbody tr td", /account is locked/i
  end

  test "preview re-posts everything the apply needs" do
    post ticketing_preview_bulk_access_documents_path,
         params: preview_params("#{@target.callsign},SPT", reason: "board approved")

    assert_select "input[name=bulk_action][value=tickets]"
    assert_select "input[name=records][value=?]", "#{@target.callsign},SPT"
    assert_select "input[name=reason][value=?]", "board approved"
  end

  test "preview refuses an empty list" do
    post ticketing_preview_bulk_access_documents_path, params: preview_params("  \n ")

    assert_response :unprocessable_entity
    assert_match(/at least one callsign/i, flash[:error])
  end

  test "preview refuses an action the page does not offer" do
    post ticketing_preview_bulk_access_documents_path,
         params: preview_params("#{@target.callsign},SPT", action: "bmidsubmitted")

    assert_match(/choose an action/i, flash[:error])
  end

  test "preview says a ticket line replaces nothing" do
    post ticketing_preview_bulk_access_documents_path,
         params: preview_params("#{@target.callsign},SPT")

    assert_select "body", /Each line creates a new document/
  end

  # --------------------------------------------------------- tickets: apply

  test "each ticket type code creates the document it names" do
    BulkUpload::TicketHandler::TYPES.each do |code, type|
      post ticketing_apply_bulk_access_documents_path,
           params: preview_params("#{@target.callsign},#{code}")

      created = documents_for(@target).last
      assert_equal type, created.type, "code #{code}"
      # NOT NULL with no database default, and the model's callback only covers
      # some of these types.
      assert_predicate created.delivery_method, :present?, "code #{code}"
    end
  end

  test "apply defaults the source and expiry years" do
    source_year, expiry_year = default_years

    post ticketing_apply_bulk_access_documents_path,
         params: preview_params("#{@target.callsign},SPT")

    created = documents_for(@target).last
    assert_equal source_year, created.source_year
    assert_equal expiry_year, created.expiry_date.year
  end

  test "gift and LSD tickets are always this year's, whatever the default is" do
    post ticketing_apply_bulk_access_documents_path,
         params: preview_params("#{@target.callsign},GIFT\n#{person(:retired_ranger).callsign},LSD")

    assert_equal Current.year, documents_for(@target).last.source_year
    assert_equal Current.year, documents_for(person(:retired_ranger)).last.source_year
  end

  test "an explicit source year still beats the override" do
    post ticketing_apply_bulk_access_documents_path,
         params: preview_params("#{@target.callsign},GIFT,#{Current.year - 1}")

    assert_equal Current.year - 1, documents_for(@target).last.source_year
  end

  test "apply sets the delivery method the type calls for" do
    post ticketing_apply_bulk_access_documents_path,
         params: preview_params("#{@target.callsign},SPT\n#{person(:retired_ranger).callsign},CRED")

    assert_equal AccessDocument::DELIVERY_NONE, documents_for(@target).last.delivery_method
    assert_equal AccessDocument::DELIVERY_WILL_CALL,
                 documents_for(person(:retired_ranger)).last.delivery_method
  end

  test "apply records the access date and stamps the reason into the comments" do
    post ticketing_apply_bulk_access_documents_path,
         params: preview_params("#{@target.callsign},CRED,#{Current.year}-08-10", reason: "board approved")

    created = documents_for(@target).last
    assert_equal "#{Current.year}-08-10", created.access_date.strftime("%Y-%m-%d")
    assert_match("#{@admin.callsign}: board approved", created.comments)
  end

  test "apply reports what changed and keeps the list" do
    post ticketing_apply_bulk_access_documents_path,
         params: preview_params("#{@target.callsign},SPT")

    assert_response :unprocessable_entity
    assert_select "[data-controller=scroll-to-top]"
    assert_select "body", /applied to 1 person/
    assert_select "textarea[name=records]", text: "#{@target.callsign},SPT"
  end

  test "apply writes nothing for a line it refused" do
    assert_no_difference "AccessDocument.count" do
      post ticketing_apply_bulk_access_documents_path,
           params: preview_params("#{@target.callsign},NOPE")
    end

    assert_select "body", /Nothing was changed/
  end

  test "apply logs one commit row naming the action and every result" do
    post ticketing_apply_bulk_access_documents_path,
         params: preview_params("#{@target.callsign},SPT", reason: "board approved")

    log = ActionLog.where(event: "bulk-upload").last
    assert_equal "tickets", log.data["action"]
    assert_equal "board approved", log.data["reason"]
    assert_equal @target.callsign, log.data["results"].first["callsign"]
    assert_equal "success", log.data["results"].first["status"]
  end

  # ------------------------------------------------------------ SAP guard

  test "a SAP is refused when a credential already gives earlier access" do
    create_document(@target, AccessDocument::STAFF_CREDENTIAL,
                    delivery_method: AccessDocument::DELIVERY_WILL_CALL,
                    access_date: "#{Current.year}-08-06")

    assert_no_difference "AccessDocument.count" do
      post ticketing_apply_bulk_access_documents_path,
           params: preview_params("#{@target.callsign},SAP,#{Current.year}-08-10")
    end

    assert_select "body", /Nothing was changed/
  end

  test "a SAP is refused when a credential already gives access at any time" do
    create_document(@target, AccessDocument::STAFF_CREDENTIAL,
                    delivery_method: AccessDocument::DELIVERY_WILL_CALL,
                    access_any_time: true)

    post ticketing_preview_bulk_access_documents_path,
         params: preview_params("#{@target.callsign},SAP,#{Current.year}-08-10")

    assert_select "tbody tr td", /already gives access at any time/
  end

  test "a SAP is allowed when the credential's access is later" do
    create_document(@target, AccessDocument::STAFF_CREDENTIAL,
                    delivery_method: AccessDocument::DELIVERY_WILL_CALL,
                    access_date: "#{Current.year}-08-20")

    post ticketing_preview_bulk_access_documents_path,
         params: preview_params("#{@target.callsign},SAP,#{Current.year}-08-10")

    assert_select "tbody tr td", /Will be applied/
  end

  # -------------------------------------------------------- SAP dates

  def sap_params(records, reason: nil) = preview_params(records, action: "wap", reason:)

  test "the SAP date action refuses a line with no date" do
    post ticketing_preview_bulk_access_documents_path, params: sap_params(@target.callsign)

    assert_select "tbody tr td", /missing access type/
  end

  test "the SAP date action refuses a date outside the August window" do
    create_document(@target, AccessDocument::SAP, delivery_method: AccessDocument::DELIVERY_EMAIL,
                                                  access_date: "#{Current.year}-08-20")

    post ticketing_preview_bulk_access_documents_path,
         params: sap_params("#{@target.callsign},#{Current.year}-09-10")

    assert_select "tbody tr td", /Access must fall between #{Current.year}-08-05 and #{Current.year}-08-26/
  end

  test "the SAP date action refuses an unparseable date" do
    post ticketing_preview_bulk_access_documents_path,
         params: sap_params("#{@target.callsign},whenever")

    assert_select "tbody tr td", /Invalid date \[whenever\]/
  end

  test "the SAP date action refuses a second column" do
    post ticketing_preview_bulk_access_documents_path,
         params: sap_params("#{@target.callsign},#{Current.year}-08-10,any")

    assert_select "tbody tr td", /Unexpected additional data/
  end

  test "the SAP date action refuses a callsign holding no pass at all" do
    post ticketing_preview_bulk_access_documents_path,
         params: sap_params("#{@target.callsign},#{Current.year}-08-10")

    assert_select "tbody tr td", /No SAP or Staff Credential to update/
  end

  test "the SAP date action refuses a pass already submitted" do
    create_document(@target, AccessDocument::SAP, status: AccessDocument::SUBMITTED,
                                                  delivery_method: AccessDocument::DELIVERY_EMAIL,
                                                  access_date: "#{Current.year}-08-10")

    post ticketing_preview_bulk_access_documents_path,
         params: sap_params("#{@target.callsign},#{Current.year}-08-12")

    assert_select "tbody tr td", /already been submitted/
  end

  test "the SAP date action never pushes access back" do
    create_document(@target, AccessDocument::SAP, delivery_method: AccessDocument::DELIVERY_EMAIL,
                                                  access_date: "#{Current.year}-08-06")

    post ticketing_preview_bulk_access_documents_path,
         params: sap_params("#{@target.callsign},#{Current.year}-08-20")

    assert_select "tbody tr td", /Access is never pushed back/
  end

  test "the SAP date action warns that anytime access would be taken away" do
    create_document(@target, AccessDocument::STAFF_CREDENTIAL,
                    delivery_method: AccessDocument::DELIVERY_WILL_CALL, access_any_time: true)

    post ticketing_preview_bulk_access_documents_path,
         params: sap_params("#{@target.callsign},#{Current.year}-08-10")

    assert_select "tbody tr td", /A date would take that away/
  end

  test "the SAP date preview says every pass the person holds is updated" do
    create_document(@target, AccessDocument::SAP, delivery_method: AccessDocument::DELIVERY_EMAIL,
                                                  access_date: "#{Current.year}-08-20")

    post ticketing_preview_bulk_access_documents_path,
         params: sap_params("#{@target.callsign},#{Current.year}-08-10")

    assert_select "body", /Every SAP and Staff Credential each person holds gets this date/
  end

  test "the SAP date action updates the pass it found instead of creating one" do
    sap = create_document(@target, AccessDocument::SAP, delivery_method: AccessDocument::DELIVERY_EMAIL,
                                                        access_date: "#{Current.year}-08-20")

    assert_no_difference "AccessDocument.count" do
      post ticketing_apply_bulk_access_documents_path,
           params: sap_params("#{@target.callsign},#{Current.year}-08-10")
    end

    assert_equal "#{Current.year}-08-10", sap.reload.access_date.strftime("%Y-%m-%d")
    assert_select "body", /applied to 1 person/
  end

  # Upstream's own comment: the write reaches every SAP and credential the
  # person holds, not only the one the preview examined.
  test "the SAP date action updates every pass the person holds" do
    sap = create_document(@target, AccessDocument::SAP, delivery_method: AccessDocument::DELIVERY_EMAIL,
                                                        access_date: "#{Current.year}-08-20")
    credential = create_document(@target, AccessDocument::STAFF_CREDENTIAL,
                                 delivery_method: AccessDocument::DELIVERY_WILL_CALL,
                                 access_date: "#{Current.year}-08-22")

    post ticketing_apply_bulk_access_documents_path,
         params: sap_params("#{@target.callsign},#{Current.year}-08-10")

    assert_equal "#{Current.year}-08-10", sap.reload.access_date.strftime("%Y-%m-%d")
    assert_equal "#{Current.year}-08-10", credential.reload.access_date.strftime("%Y-%m-%d")
  end

  test "the word any sets access at any time" do
    sap = create_document(@target, AccessDocument::SAP, delivery_method: AccessDocument::DELIVERY_EMAIL,
                                                        access_date: "#{Current.year}-08-20")

    post ticketing_apply_bulk_access_documents_path, params: sap_params("#{@target.callsign},ANY")

    assert_predicate sap.reload, :access_any_time
    assert_nil sap.access_date
  end

  # ------------------------------------------------------------------ edit

  test "going back to edit keeps the list and the chosen action" do
    post ticketing_edit_bulk_access_documents_path,
         params: sap_params("#{@target.callsign},#{Current.year}-08-10", reason: "arrival changed")

    assert_response :unprocessable_entity
    assert_select "textarea[name=records]", text: "#{@target.callsign},#{Current.year}-08-10"
    assert_select "select[name=bulk_action] option[selected][value=wap]"
    assert_select "input[name=reason][value=?]", "arrival changed"
  end

  # ------------------------------------------------- several lines per person

  # The repeat check keys on the whole record, not the callsign: one person
  # legitimately takes two documents of different types on one list, and keying
  # it on the callsign alone silently threw the second line away.
  test "two lines for one person asking for different documents both apply" do
    assert_difference "AccessDocument.where(person_id: #{@target.id}).count", 2 do
      post ticketing_bulk_access_documents_path,
           params: preview_params("#{@target.callsign},CRED\n#{@target.callsign},VP")
    end

    types = documents_for(@target).pluck(:type)
    assert_includes types, AccessDocument::STAFF_CREDENTIAL
    assert_includes types, AccessDocument::VEHICLE_PASS_SP
  end

  test "the same line twice is still counted once" do
    assert_difference "AccessDocument.where(person_id: #{@target.id}).count", 1 do
      post ticketing_bulk_access_documents_path,
           params: preview_params("#{@target.callsign},CRED\n#{@target.callsign},CRED")
    end
  end

  # ------------------------------------------------------------------ audit

  test "apply records the reason on the document's audit row" do
    post ticketing_bulk_access_documents_path,
         params: preview_params("#{@target.callsign},SPT", reason: "2026 ticket batch")

    document = documents_for(@target).last
    audit = ActionLog.where(target_person_id: @target.id, event: "access-document-create").last
    assert_not_nil audit, "AccessDocument is an audit model, so creating one writes a row"
    assert_equal "2026 ticket batch", audit.message
    assert_equal AccessDocument::SPT, document.type
  end

  # ---------------------------------------------------- SAP any-time guard

  # update_saps_for_person writes access_any_time on EVERY qualified, claimed
  # and banked pass and credential the person holds, but the candidate rule
  # prefers a claimed row -- so checking only the candidate let a date silently
  # revoke any-time access on a credential no preview row ever named.
  test "a date is refused when any credential gives any-time access, not just the candidate" do
    create_document(@target, AccessDocument::SAP,
                    status: AccessDocument::CLAIMED, access_date: "#{Current.year}-08-20")
    credential = create_document(@target, AccessDocument::STAFF_CREDENTIAL, access_any_time: true)

    post ticketing_preview_bulk_access_documents_path,
         params: sap_params("#{@target.callsign},#{Current.year}-08-18")

    assert_response :unprocessable_entity
    assert_select "tbody tr td", /gives access at any time/
    assert credential.reload.access_any_time, "the preview must not have written anything"
  end
end
