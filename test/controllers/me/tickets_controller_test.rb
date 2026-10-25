# frozen_string_literal: true

require "test_helper"

class Me::TicketsControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TrainingSlotTestHelper

  setup do
    sign_in_as(person(:active_ranger))
  end

  def person_event_for(who)
    PersonEvent.find_for_person_year(person(who).id, Current.year)
  end

  # --- Authorization -------------------------------------------------------

  test "index allows statuses not listed in except" do
    get me_tickets_url

    assert_response :success
  end

  test "index rejects statuses listed in except" do
    sign_out
    sign_in_as(person(:auditor_ranger))

    get me_tickets_url

    assert_redirected_to me_root_path
    assert_equal "You are not authorized to view the page.", flash[:error]
  end

  test "past prospective is blocked" do
    sign_out
    sign_in_as(person(:past_prospective_ranger))

    get me_tickets_url

    assert_redirected_to me_root_path
    assert_equal "You are not authorized to view the page.", flash[:error]
  end

  test "applicant sees the SAP-only hub" do
    sign_out
    sign_in_as(person(:prospective_ranger))

    get me_tickets_url

    assert_response :success
    assert_select "h1", text: /Setup Access Pass/
  end

  # --- Session bookkeeping -------------------------------------------------

  test "visiting the hub stamps ticketing_last_visited_at" do
    assert_nil person_event_for(:active_ranger)&.ticketing_last_visited_at

    get me_tickets_url

    assert_response :success
    assert_not_nil person_event_for(:active_ranger).ticketing_last_visited_at
  end

  test "first section GET stamps ticketing_started_at" do
    assert_nil person_event_for(:active_ranger)&.ticketing_started_at

    get me_tickets_ticket_url

    assert_response :success
    assert_not_nil person_event_for(:active_ranger).ticketing_started_at
  end

  test "finish stamps ticketing_finished_at and redirects to the hub" do
    assert_nil person_event_for(:active_ranger)&.ticketing_finished_at

    post me_tickets_finish_url

    assert_redirected_to me_tickets_path
    assert_not_nil person_event_for(:active_ranger).ticketing_finished_at
  end

  test "the finished hub still links to every section for adjustment" do
    post me_tickets_finish_url
    get me_tickets_url

    assert_response :success
    # Regression: after finishing, the checklist must stay reachable so a member
    # can still adjust the VP, provisions, SO SAPs, etc. — not just the ticket.
    assert_select "a[href=?]", me_tickets_vehicle_pass_path
    assert_select "a[href=?]", me_tickets_provisions_path
    assert_select "a[href=?]", me_tickets_sap_so_path
  end

  # --- update_status -------------------------------------------------------

  test "update_status banks an owned ticket" do
    patch me_tickets_document_status_url(access_document(:ar_spt).id), params: { status: "banked" }

    assert_redirected_to me_tickets_path
    assert_equal "Ticket updated.", flash[:notice]
    assert_equal AccessDocument::BANKED, access_document(:ar_spt).reload.status
  end

  test "update_status on another person's document is not found" do
    patch me_tickets_document_status_url(access_document(:ig_staff_credential).id), params: { status: "banked" }

    assert_response :not_found
  end

  test "update_status claiming with a delivery_method also sets delivery on the ticket and vehicle pass" do
    patch me_tickets_document_status_url(access_document(:ar_spt).id),
          params: { status: "claimed", delivery_method: "postal" }

    assert_redirected_to me_tickets_path
    spt = access_document(:ar_spt).reload
    assert_equal AccessDocument::CLAIMED, spt.status
    assert_equal AccessDocument::DELIVERY_POSTAL, spt.delivery_method
    # One choice covers everything deliverable: the claimed VP follows along.
    assert_equal AccessDocument::DELIVERY_POSTAL, access_document(:ar_vp_sp).reload.delivery_method
  end

  test "update_status rejects an invalid delivery_method without claiming" do
    patch me_tickets_document_status_url(access_document(:ar_spt).id),
          params: { status: "claimed", delivery_method: "carrier_pigeon" }

    assert_redirected_to me_tickets_path
    assert_not_nil flash[:alert]
    assert_equal AccessDocument::QUALIFIED, access_document(:ar_spt).reload.status,
                 "an invalid delivery method must not claim the ticket"
  end

  test "update_status flashes on an illegal transition" do
    # An SP ticket cannot be reverted to qualified.
    patch me_tickets_document_status_url(access_document(:ar_spt).id), params: { status: "qualified" }

    assert_redirected_to me_tickets_path
    assert_not_nil flash[:alert]
    assert_equal AccessDocument::QUALIFIED, access_document(:ar_spt).reload.status,
                 "the document should be unchanged"
  end

  # --- update_sap_so -------------------------------------------------------

  test "update_sap_so creates a new SO SAP" do
    assert_difference -> { AccessDocument.so_sap_count(person(:active_ranger).id) }, 1 do
      patch me_tickets_sap_so_url, params: { names: [{ id: "new", name: "Second SO" }] }
    end

    assert_redirected_to me_tickets_sap_so_path
    assert_equal "SO SAP passes updated.", flash[:notice]
  end

  test "update_sap_so renames and claims an existing SO SAP" do
    patch me_tickets_sap_so_url, params: { names: [{ id: access_document(:ar_sapso).id, name: "Renamed SO" }] }

    assert_redirected_to me_tickets_sap_so_path
    ar_sapso = access_document(:ar_sapso).reload
    assert_equal "Renamed SO", ar_sapso.name
    assert_equal AccessDocument::CLAIMED, ar_sapso.status
  end

  test "update_sap_so cancels an existing SO SAP when the name is blank" do
    patch me_tickets_sap_so_url, params: { names: [{ id: access_document(:ar_sapso).id, name: "" }] }

    assert_redirected_to me_tickets_sap_so_path
    assert_equal AccessDocument::CANCELLED, access_document(:ar_sapso).reload.status
  end

  test "update_sap_so ignores blank new slots" do
    assert_no_difference -> { AccessDocument.so_sap_count(person(:active_ranger).id) } do
      patch me_tickets_sap_so_url, params: { names: [{ id: "new", name: "" }] }
    end

    assert_redirected_to me_tickets_sap_so_path
    assert_equal "SO SAP passes updated.", flash[:notice]
    assert_nil flash[:alert]
  end

  test "update_sap_so renames an existing SO SAP alongside a blank new slot" do
    assert_no_difference -> { AccessDocument.so_sap_count(person(:active_ranger).id) } do
      patch me_tickets_sap_so_url,
            params: { names: [{ id: access_document(:ar_sapso).id, name: "Renamed SO" }, { id: "new", name: "" }] }
    end

    assert_redirected_to me_tickets_sap_so_path
    assert_equal "Renamed SO", access_document(:ar_sapso).reload.name
    assert_nil flash[:alert]
  end

  test "update_sap_so rejects a new pass over the limit" do
    sign_out
    sign_in_as(person(:ranger_with_custom_gender))

    assert_no_difference -> { AccessDocument.so_sap_count(person(:ranger_with_custom_gender).id) } do
      patch me_tickets_sap_so_url, params: { names: [{ id: "new", name: "Third SO" }] }
    end

    assert_redirected_to me_tickets_sap_so_path
    assert_not_nil flash[:alert]
  end

  # --- update_provisions ---------------------------------------------------

  test "update_provisions claims earned provisions" do
    patch me_tickets_provisions_url, params: { status: "claimed" }

    assert_redirected_to me_tickets_provisions_path
    assert_equal "Provisions updated.", flash[:notice]

    earned = provision(:ar_meals).reload
    assert_equal Provision::CLAIMED, earned.status
    assert_equal Current.year, earned.consumed_year
  end

  test "update_provisions is rejected when the person has allocated provisions" do
    sign_out
    sign_in_as(person(:ranger_with_custom_gender))

    patch me_tickets_provisions_url, params: { status: "claimed" }

    assert_redirected_to me_tickets_provisions_path
    assert_not_nil flash[:alert]
    assert_equal Provision::AVAILABLE, provision(:cg_allocated_meals).reload.status,
                 "allocated provisions should be untouched"
  end

  # --- update_delivery -----------------------------------------------------

  test "update_delivery sets the method on all non-special deliverables" do
    patch me_tickets_delivery_url, params: { delivery_method: "postal" }

    assert_redirected_to me_tickets_path
    assert_equal "Delivery method updated.", flash[:notice]
    assert_equal AccessDocument::DELIVERY_POSTAL, access_document(:ar_spt).reload.delivery_method
  end

  test "update_delivery with a document_id claims a single gift document and keeps the chosen delivery method" do
    patch me_tickets_delivery_url,
          params: { delivery_method: "will_call", document_id: access_document(:ar_gift).id }

    assert_redirected_to me_tickets_path
    gift = access_document(:ar_gift).reload
    assert_equal AccessDocument::CLAIMED, gift.status
    # Regression: the claim must not leave delivery_method reset to none.
    assert_equal AccessDocument::DELIVERY_WILL_CALL, gift.delivery_method
  end

  # --- Wizard walkthrough ---------------------------------------------------

  test "section pages show wizard navigation while ticketing is unfinished" do
    get me_tickets_ticket_url

    assert_response :success
    assert_match "Step 1 of", response.body
    # The event ticket decision blocks Continue until claimed or banked.
    assert_match "Make your choice above to continue", response.body
  end

  test "claim buttons carry status and delivery in the link so Turbo submits them" do
    get me_tickets_ticket_url

    assert_select "a[href=?][data-turbo-method='patch']",
                  me_tickets_document_status_path(access_document(:ar_spt), status: "claimed", delivery_method: "will_call")
  end

  test "wizard blocks steps past an undecided event ticket" do
    get me_tickets_sap_url

    assert_redirected_to me_tickets_ticket_path
    assert_equal "Finish your event ticket choices first.", flash[:warning]
  end

  test "wizard unblocks later steps once the ticket is claimed with a delivery method" do
    patch me_tickets_document_status_url(access_document(:ar_spt).id),
          params: { status: "claimed", delivery_method: "will_call" }

    get me_tickets_sap_url

    assert_response :success

    get me_tickets_review_url

    assert_response :success
  end

  test "a claimed ticket without a delivery method still blocks later steps" do
    patch me_tickets_document_status_url(access_document(:ar_spt).id), params: { status: "claimed" }

    get me_tickets_review_url

    assert_redirected_to me_tickets_ticket_path
    assert_equal "Finish your event ticket choices first.", flash[:warning]
  end

  test "review summarizes the choices and offers the finish action" do
    patch me_tickets_document_status_url(access_document(:ar_spt).id),
          params: { status: "claimed", delivery_method: "will_call" }

    get me_tickets_review_url

    assert_response :success
    assert_match "A Special Price Ticket", response.body
    assert_select "a[href=?][data-turbo-method='post']", me_tickets_finish_path
  end

  test "finished members are not blocked and see no wizard chrome" do
    post me_tickets_finish_url

    get me_tickets_sap_url

    assert_response :success

    get me_tickets_ticket_url

    assert_response :success
    assert_no_match "Step 1 of", response.body
    assert_match "Back to Tickets &amp; Provisions", response.body
  end

  # --- Hub landing -----------------------------------------------------------

  test "the unfinished hub shows the walkthrough launcher instead of the card grid" do
    get me_tickets_url

    assert_response :success
    assert_match "Start ticketing", response.body
    # The compact step list links every step, including the confirmation row.
    assert_select "a[href=?]", me_tickets_review_path
    assert_no_match "Adjust Your Choices", response.body
  end

  test "the launcher offers Continue once ticketing has started" do
    get me_tickets_ticket_url
    get me_tickets_url

    assert_response :success
    assert_match "Continue ticketing", response.body
  end

  # --- Vehicle pass ----------------------------------------------------------

  test "vehicle pass page states the member did not qualify when no pass was issued" do
    AccessDocument.where(person_id: person(:active_ranger).id,
                         type: [AccessDocument::VEHICLE_PASS_SP, AccessDocument::VEHICLE_PASS_GIFT]).delete_all
    patch me_tickets_document_status_url(access_document(:ar_spt).id),
          params: { status: "claimed", delivery_method: "will_call" }

    get me_tickets_vehicle_pass_url

    assert_response :success
    assert_match "You didn't qualify for a Vehicle Pass this year", response.body
  end

  test "update_sap_so refuses to mutate a document that is not a SO SAP" do
    ticket = access_document(:ar_spt)
    original_status = ticket.status

    patch me_tickets_sap_so_url, params: { names: [{ id: ticket.id, name: "" }] }

    assert_redirected_to me_tickets_sap_so_path
    assert_not_nil flash[:alert]
    assert_equal original_status, ticket.reload.status,
                 "a non-SO-SAP document must not be cancelled through the SO SAP endpoint"
  end

  test "the provisions and SO SAP sections render once ticketing is finished" do
    post me_tickets_finish_url

    get me_tickets_provisions_url
    assert_response :success

    get me_tickets_sap_so_url
    assert_response :success
  end

  test "the hub shows the announcement before ticketing opens" do
    setting(:ticketing_period).update!(value: TicketingInfo::PERIOD_ANNOUNCE)

    get me_tickets_url

    assert_response :success
    assert_select "dl.instruction-list"
  end

  # --- Closed period: applicants -------------------------------------------

  def close_ticketing_as_applicant
    setting(:ticketing_period).update!(value: TicketingInfo::PERIOD_CLOSED)
    sign_out
    sign_in_as(person(:prospective_ranger))
    Position.create!(id: Position::TRAINING, title: "Training", type: Position::TYPE_TRAINING, active: true)
  end

  test "an applicant signed up for In-Person Training is told they get a SAP" do
    close_ticketing_as_applicant
    sign_up(person(:prospective_ranger), create_slot(Position.find(Position::TRAINING), begins: Current.time + 1.week))

    get me_tickets_url

    assert_response :success
    assert_select "p", text: /You get a Setup Access Pass/
    assert_select "p", text: /signed up for In-Person Training/
  end

  test "an applicant without In-Person Training is told they get no SAP" do
    close_ticketing_as_applicant

    get me_tickets_url

    assert_response :success
    assert_select "p", text: /You will not receive a Setup Access Pass/
    assert_select "p", text: /You get a Setup Access Pass/, count: 0
  end
end
