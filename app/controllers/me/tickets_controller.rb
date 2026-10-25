# frozen_string_literal: true

# Tickets & Provisions self-service ("Where's My Ticket") for /me/tickets.
#
# The hub (#index) is always reachable by eligible members; the individual
# section pages and write actions are only reachable when the ticketing window
# is open, the member is not an applicant, and the member has linked their
# Burner Profile (BPGUID).
class Me::TicketsController < ApplicationController
  layout "me"

  # Auditors have no ticket package; past-prospectives are no longer eligible.
  authorize_status except: [Person::AUDITOR, Person::PAST_PROSPECTIVE]

  # Actions that render a page and therefore need the package + ticketing info.
  RENDER_ACTIONS = %i[index ticket gift vehicle_pass provisions sap sap_so review].freeze
  # Section pages (everything the member can open other than the hub itself).
  SECTION_ACTIONS = (RENDER_ACTIONS - %i[index]).freeze

  # Notices shown when the walkthrough sends the member back to an undecided
  # blocking step. Only non-optional sections can block (see the presenter).
  WIZARD_BLOCK_NOTICES = {
    ticket: "Finish your event ticket choices first."
  }.freeze

  # Delivery methods a member is allowed to choose.
  DELIVERY_METHODS = [
    AccessDocument::DELIVERY_WILL_CALL,
    AccessDocument::DELIVERY_POSTAL,
    AccessDocument::DELIVERY_PRIORITY
  ].freeze

  # Statuses a member is allowed to request for one of their documents.
  STATUS_CHANGES = [
    AccessDocument::BANKED,
    AccessDocument::CLAIMED,
    AccessDocument::QUALIFIED
  ].freeze

  # Provision statuses a member is allowed to request for their earned provisions.
  PROVISION_STATUSES = [Provision::BANKED, Provision::CLAIMED].freeze

  before_action :set_ticketing_info
  before_action :require_ticketing_access, except: :index
  before_action :stamp_started, only: SECTION_ACTIONS
  before_action :build_package, only: RENDER_ACTIONS
  before_action :enforce_wizard_order, only: SECTION_ACTIONS

  helper_method :wizard_mode?

  # --- Hub -----------------------------------------------------------------

  def index
    @missing_bpguid = missing_bpguid?
    person_event.ticketing_last_visited_at = Current.time
    person_event.save(validate: false)
  end

  # --- Section pages -------------------------------------------------------

  def ticket; end

  def gift; end

  def vehicle_pass; end

  def provisions; end

  def sap; end

  def sap_so; end

  # Final wizard step: confirm the choices, then POST finish.
  def review; end

  # --- Write actions -------------------------------------------------------

  # Change the status (claim / bank / release) of a single document. Claiming
  # may carry a delivery_method so the member picks delivery in the same click;
  # the choice applies to every non-special deliverable (ticket + Vehicle Pass).
  def update_status
    document = AccessDocument.find_for_person(current_user.id, params[:id])
    method = params[:delivery_method].present? ? delivery_method_param : nil

    AccessDocument.transaction do
      AccessDocumentStatusChange.new(
        person_id: current_user.id,
        document: document,
        status: status_param
      ).call
      set_delivery_for_all(method) if method && status_param == AccessDocument::CLAIMED
    end

    redirect_back_or_to me_tickets_path, notice: "Ticket updated."
  rescue AccessDocumentStatusChange::InvalidTransition => e
    redirect_back_or_to me_tickets_path, alert: e.message
  end

  # Set the delivery method for all deliverable tickets, or claim-and-set for a
  # single gift/special document.
  def update_delivery
    method = delivery_method_param
    document_id = params[:document_id]

    if document_id.present?
      claim_and_set_delivery(document_id, method)
    else
      set_delivery_for_all(method)
    end

    redirect_back_or_to me_tickets_path, notice: "Delivery method updated."
  rescue AccessDocumentStatusChange::InvalidTransition => e
    redirect_back_or_to me_tickets_path, alert: e.message
  end

  # Create/claim/cancel the member's Significant Other SAP passes.
  def update_sap_so
    max = @ticketing_info.sap_so_max

    AccessDocument.transaction do
      Array(params[:names]).first(10).each { |row| apply_sap_so_row(row, max) }
    end

    redirect_back_or_to me_tickets_sap_so_path, notice: "SO SAP passes updated."
  rescue AccessDocumentStatusChange::InvalidTransition => e
    redirect_back_or_to me_tickets_sap_so_path, alert: e.message
  end

  # Bank or claim all of the member's earned (non-allocated) provisions at once.
  def update_provisions
    status = provision_status_param

    if Provision.have_allocated?(current_user.id)
      raise AccessDocumentStatusChange::InvalidTransition,
            "You have allocated provisions. Earned provisions cannot be adjusted."
    end

    rows = Provision.retrieve_earned(current_user.id).to_a
    if rows.empty?
      raise AccessDocumentStatusChange::InvalidTransition, "You have no earned provisions."
    end

    Provision.transaction do
      rows.each do |row|
        row.status = status
        row.consumed_year = Current.year if status == Provision::CLAIMED
        row.audit_reason = "provisions #{status}"
        row.save!(validate: false)
      end
    end

    redirect_back_or_to me_tickets_provisions_path, notice: "Provisions updated."
  rescue AccessDocumentStatusChange::InvalidTransition => e
    redirect_back_or_to me_tickets_provisions_path, alert: e.message
  end

  # Mark the member's ticketing session as finished and return to the hub.
  def finish
    person_event.ticketing_finished_at = Current.time
    person_event.save(validate: false)

    redirect_to me_tickets_path, notice: "Ticketing choices recorded."
  end

  private

  # --- Delivery helpers ----------------------------------------------------

  def claim_and_set_delivery(document_id, method)
    document = AccessDocument.find_for_person(current_user.id, document_id)
    unless document.special_document?
      raise AccessDocumentStatusChange::InvalidTransition, "Access document is not a Special Type document."
    end

    AccessDocument.transaction do
      AccessDocumentStatusChange.new(
        person_id: current_user.id,
        document: document,
        status: AccessDocument::CLAIMED
      ).call
      # .call claims a freshly-loaded copy, so reload before setting delivery:
      # otherwise the stale in-memory "qualified" status makes the model's
      # set_delivery_method_by_type callback reset delivery_method to none.
      document.reload
      set_delivery(document, method)
    end
  end

  def set_delivery_for_all(method)
    AccessDocument.transaction do
      AccessDocument.find_all_available_deliverables_for_person(current_user.id).each do |ticket|
        next if ticket.special_document?

        set_delivery(ticket, method)
      end
    end
  end

  def set_delivery(document, method)
    document.delivery_method = method
    document.audit_reason = "Delivery update"
    document.save!(validate: false)
  end

  # --- SO SAP helpers ------------------------------------------------------

  def apply_sap_so_row(row, max)
    name = row[:name].to_s.strip
    id = row[:id]

    if id == "new"
      # The page always submits every slot; an empty new slot is just unused.
      create_sap_so(name, max) if name.present?
    else
      update_existing_sap_so(id, name)
    end
  end

  def create_sap_so(name, max)
    if AccessDocument.so_sap_count(current_user.id) >= max
      raise AccessDocumentStatusChange::InvalidTransition,
            "New pass would exceed the limit of #{max} allowed SO SAP passes."
    end

    AccessDocument.create_so_sap(current_user.id, Current.year, name)
  end

  def update_existing_sap_so(id, name)
    sap = AccessDocument.find_for_person(current_user.id, id)
    # Only SO SAP rows go through this path. Guard the type so a member cannot
    # POST another of their own document ids (ticket, VP, gift) and force a
    # status change that bypasses the AccessDocumentStatusChange state machine.
    unless sap.type == AccessDocument::SAPSO
      raise AccessDocumentStatusChange::InvalidTransition, "Not a Significant Other SAP document."
    end

    if name.blank?
      sap.status = AccessDocument::CANCELLED
    else
      sap.status = AccessDocument::CLAIMED
      sap.name = name
    end

    sap.audit_reason = "SO SAP update"
    sap.save!(validate: false)
  end

  # --- Whitelisting --------------------------------------------------------

  def delivery_method_param
    method = params[:delivery_method]
    unless DELIVERY_METHODS.include?(method)
      raise AccessDocumentStatusChange::InvalidTransition, "Invalid delivery method."
    end

    method
  end

  def status_param
    status = params[:status]
    unless STATUS_CHANGES.include?(status)
      raise AccessDocumentStatusChange::InvalidTransition, "Unknown status action."
    end

    status
  end

  def provision_status_param
    status = params[:status]
    unless PROVISION_STATUSES.include?(status)
      raise AccessDocumentStatusChange::InvalidTransition, "Invalid provision status."
    end

    status
  end

  # --- Access / session bookkeeping ---------------------------------------

  def set_ticketing_info
    @ticketing_info = TicketingInfo.new
  end

  def build_package
    @ticket_package = TicketAndProvisionsPackage.new(current_user.id)
    @presenter = TicketOverviewPresenter.new(@ticket_package, @ticketing_info)
  end

  # The member is walked through the sections until they confirm (finish).
  def wizard_mode?
    ticketing_accessible? && person_event.ticketing_finished_at.nil?
  end

  # In wizard mode a member cannot open a step past an undecided blocking step
  # (the event ticket, whose claim includes delivery); deep links are sent back
  # to that step.
  def enforce_wizard_order
    return unless wizard_mode?

    blocking = @presenter.first_blocking_step(before: action_name.to_sym)
    return unless blocking

    redirect_to public_send("me_tickets_#{blocking}_path"), warning: WIZARD_BLOCK_NOTICES[blocking]
  end

  # Section pages and writes are gated on an open window, a non-applicant, and a
  # linked Burner Profile. Otherwise the member is sent back to the hub.
  def require_ticketing_access
    return if ticketing_accessible?

    redirect_to me_tickets_path
  end

  def ticketing_accessible?
    !missing_bpguid? &&
      @ticketing_info.period == TicketingInfo::PERIOD_OPEN &&
      !current_user.is_applicant?
  end

  # Mirror of Milestones/MissingBpguid: a non-auditor without a linked Burner Profile.
  def missing_bpguid?
    current_user.missing_bpguid?
  end

  def stamp_started
    return if person_event.ticketing_started_at.present?

    person_event.ticketing_started_at = Current.time
    person_event.save(validate: false)
  end

  def person_event
    @person_event ||= PersonEvent.first_or_new_for_person_year(current_user.id, current_year)
  end
end
