# frozen_string_literal: true

class TicketOverviewPresenter
  include ActionView::Helpers::NumberHelper

  attr_reader :package, :ticketing_info

  # Ordered list of the open-period checklist sections. Each maps to one
  # section page under /me/tickets and is rendered as one card on the hub.
  # Delivery is not a section: it is chosen while claiming the event ticket.
  SECTION_KEYS = %i[ticket gift vehicle_pass provisions sap sap_so].freeze

  # One row of the open-period checklist. `state` is one of:
  #   :decided        — the member has made this choice; nothing more to do
  #   :needs_decision — the member still has to choose something here
  #   :locked         — cannot be decided yet (a prerequisite is unmet)
  #   :not_applicable — the member has nothing to decide here (card hidden)
  #
  # `summary` is a short, human one-line description of the current state.
  # `optional` marks decisions that never block finishing (they are not added
  # to the outstanding-tasks list even while `needs_decision`).
  SectionStatus = Struct.new(:key, :state, :summary, :optional, keyword_init: true) do
    def decided? = state == :decided

    def needs_decision? = state == :needs_decision

    def locked? = state == :locked

    def not_applicable? = state == :not_applicable

    def applicable? = state != :not_applicable
  end

  # Blocking message shared by the hub checklist and the review-page task list.
  DELIVERY_UNDECIDED_MESSAGE = "Choose how your ticket reaches you: Will Call or mail."

  def initialize(package, ticketing_info)
    @package = package
    @ticketing_info = ticketing_info
  end

  # The claimed ticket (if any)
  def ticket
    @ticket ||= package.access_documents.find { |ad| ad.regular_ticket? && ad.is_using? }
  end

  # Is using a Staff Credential
  def using_staff_credential?
    ticket&.staff_credential?
  end

  # Does any SC exist (qualified or claimed)
  def have_staff_credential?
    package.access_documents.any? { |ad| ad.staff_credential? && ad.available? }
  end

  # Has qualified ticket but not claimed
  def ticket_not_claimed?
    package.access_documents.any? { |ad| ad.regular_ticket? && ad.is_qualified? }
  end

  # All tickets are banked
  def all_tickets_banked?
    tickets = package.access_documents.select(&:regular_ticket?)
    tickets.present? && tickets.all?(&:is_banked?)
  end

  # VP is claimed
  def using_vehicle_pass?
    package.access_documents.any?(&:using_vehicle_pass?)
  end

  # Delivery method
  def using_mail?
    ticket&.delivery_postal? || ticket&.delivery_priority?
  end

  def using_will_call?
    ticket&.delivery_will_call?
  end

  # The effective SAP (SC or actual SAP)
  def effective_sap
    return ticket if using_staff_credential?

    package.access_documents.find { |ad| ad.type == AccessDocument::SAP && ad.is_using? }
  end

  # Has a claimed SAP/SC
  def using_sap?
    effective_sap.present?
  end

  def using_gift_ticket?
    package.gift_items.any? { |gift| gift.is_using? }
  end

  # List of SO SAPs
  def sap_so_list
    package.access_documents.select { |ad| ad.type == AccessDocument::SAPSO && ad.is_using? }
  end

  # Special ticket counts
  def gift_ticket_count
    package.gift_items.count { |ad| ad.type == AccessDocument::GIFT }
  end

  def lsd_ticket_count
    package.lsd_items.count { |ad| ad.type == AccessDocument::LSD }
  end

  def lsd_vp_count
    package.lsd_items.count { |ad| ad.type == AccessDocument::VEHICLE_PASS_LSD }
  end

  def radios
    package.provisions&.radios || 0
  end

  class ProvisionItem
    attr_accessor :icon, :label

    def initialize(icon, label)
      @icon = icon
      @label = label
    end
  end

  # Provision items for display
  def provision_items
    provisions = package.provisions

    return [] unless provisions

    items = []
    items << ProvisionItem.new("utensils", provisions.meals.title) if provisions.have_meals
    items << ProvisionItem.new("shower", "Wet Spot Access") if provisions.showers
    if provisions.radios.positive?
      items << ProvisionItem.new(
        "walkie-talkie",
        (provisions.radios > 1) ? "#{provisions.radios} Event Radios" : "Event Radio"
      )
    end

    items
  end

  # Does the user have any items with entry date restrictions?
  def has_entry_date_restrictions?
    effective_sap.present? && effective_sap.access_date.present? && !effective_sap.access_any_time
  end

  # Does the user have any paid items (SPT or VP)?
  def has_paid_items?
    using_special_priced_ticket? || (using_vehicle_pass? && using_special_priced_ticket?)
  end

  # Is using a Special-Priced Ticket (not Staff Credential)
  def using_special_priced_ticket?
    ticket.present? && !ticket.staff_credential?
  end

  # Pricing summary for claimed paid items
  def pricing_summary
    return nil unless has_paid_items?

    items = []
    items << { label: "Special-Priced Ticket", cost: ticketing_info.spt_cost } if using_special_priced_ticket?
    items << { label: "Vehicle Pass", cost: ticketing_info.sp_vp_cost } if using_vehicle_pass? && using_special_priced_ticket?
    items
  end

  # Total cost of paid items. Costs come from settings and may be unset (nil).
  def total_cost
    return 0 unless has_paid_items?

    total = 0
    total += ticketing_info.spt_cost.to_i if using_special_priced_ticket?
    total += ticketing_info.sp_vp_cost.to_i if using_vehicle_pass? && using_special_priced_ticket?
    total
  end

  # Earliest entry date from all access documents
  def earliest_entry_date
    return nil unless effective_sap

    effective_sap.access_date
  end

  # Does the user have provisions that need explanation?
  def has_provisions?
    provision_items.any?
  end

  # --- Open-period checklist ------------------------------------------------

  # The Vehicle Pass document the member is actually using (claimed/submitted).
  def vehicle_pass
    @vehicle_pass ||= package.access_documents.find(&:using_vehicle_pass?)
  end

  # An available (qualified/claimed/submitted) Vehicle Pass document, if any.
  def vehicle_pass_doc
    @vehicle_pass_doc ||= package.access_documents.find do |ad|
      [AccessDocument::VEHICLE_PASS_SP, AccessDocument::VEHICLE_PASS_GIFT].include?(ad.type) && ad.available?
    end
  end

  # The single deliverable the delivery choice applies to: the ticket in use,
  # otherwise the Vehicle Pass in use.
  def primary_deliverable
    ticket || vehicle_pass
  end

  # Ordered checklist of every section for the open-period hub.
  def sections
    SECTION_KEYS.map { |key| section_status(key) }
  end

  # Status for a single section key.
  def section_status(key)
    send("#{key}_section_status")
  end

  # Blocking tasks the member must finish before ticketing is complete.
  # Ported from ticket-summary.js `unfinishedItems`.
  def outstanding_tasks
    tasks = []
    tasks << "Claim or bank your event ticket." if ticket_not_claimed?
    tasks << DELIVERY_UNDECIDED_MESSAGE if delivery_undecided?(primary_deliverable)
    tasks
  end

  # One-line description of how the in-use items arrive, for the review page.
  # nil while there is nothing to deliver or the choice is still open.
  def delivery_summary
    item = primary_deliverable
    return nil if item.nil?
    return "Pickup at Staff Credentialing (Will Call)." if using_staff_credential?
    return nil if item.delivery_none?

    "Delivery: #{delivery_label(item)}."
  end

  # Items claimed (and about to be submitted). Ported from ticket-summary.js.
  def claimed_items
    items = []
    items << "A #{ticket.type_label}" if ticket && claimed?(ticket)
    package.gift_items.each { |g| items << "A #{g.type_label}" if claimed?(g) }
    items << "A #{vehicle_pass.type_label}" if vehicle_pass && claimed?(vehicle_pass)
    items << "A SAP for yourself" if using_sap?
    sap_so_list.each do |so|
      items << "A S.O. SAP for <strong>#{so.name}</strong>".html_safe
    end
    provision_items.each { |p| items << p.label } unless package.provisions_banked
    items
  end

  # Items the member could have claimed but did not. Ported from ticket-summary.js.
  def unclaimed_items
    items = []
    items << "No Vehicle Pass to drive into the event." if vehicle_pass_doc && !using_vehicle_pass?
    items << "No Setup Access Pass for yourself." unless using_sap?
    items << "No Setup Access Passes for significant others." if sap_so_list.empty?
    items
  end

  # Items being banked for a future year, with their expiry. Ported from
  # ticket-summary.js `bankedItems`.
  def banked_items
    items = []
    package.access_documents.select { |ad| ad.regular_ticket? && ad.is_banked? }.each do |t|
      items << { name: "A #{t.type_label}", expires: format_expiry(t.expiry_date) }
    end
    if package.provisions_banked
      provision_items.each { |p| items << { name: p.label, expires: nil } }
    end
    items
  end

  # Items already submitted to Burning Man ticketing (rare mid-window state).
  def submitted_items
    package.access_documents
           .select { |ad| ad.status == AccessDocument::SUBMITTED }
           .map(&:type_label)
  end

  # --- Wizard (walkthrough until ticketing is finished) ----------------------

  # Candidate walkthrough steps, in order. Gift and provisions only appear when
  # the member has any; vehicle_pass always appears so the page can say the
  # member didn't qualify when no pass was issued.
  WIZARD_KEYS = %i[ticket gift vehicle_pass provisions sap sap_so].freeze

  # Ordered steps of the walkthrough, ending with the confirmation step.
  def wizard_steps
    @wizard_steps ||= begin
                        keys = WIZARD_KEYS.dup
                        keys.delete(:gift) if package.gift_items.empty?
                        keys.delete(:provisions) if package.provisions.nil?
                        keys << :review
                        keys
                      end
  end

  # A step the member cannot continue past until its decision is made. Only
  # non-optional pending decisions block (the event ticket, whose claim now
  # includes delivery) — for optional items, taking no action is a valid choice.
  def wizard_blocked?(key)
    return false if key == :review

    status = section_status(key)
    status.needs_decision? && !status.optional
  end

  # First blocked step, looking only at steps before `before` when given.
  # A `before` key that isn't a wizard step checks the whole list.
  def first_blocking_step(before: nil)
    keys = wizard_steps
    keys = keys.take(keys.index(before) || keys.size) if before
    keys.find { |key| wizard_blocked?(key) }
  end

  # Where "Start/Continue ticketing" lands: the first step still needing a
  # decision, or the confirmation step when nothing is pending.
  def next_undecided_step
    wizard_steps.find { |key| key != :review && section_status(key).needs_decision? } || :review
  end

  private

  def claimed?(document)
    document.status == AccessDocument::CLAIMED
  end

  def format_expiry(date)
    date&.year
  end

  # --- Per-section status logic --------------------------------------------

  def ticket_section_status
    regular = package.access_documents.select(&:regular_ticket?)
    return section(:ticket, :not_applicable, "No event ticket earned this year.") if regular.empty?

    if ticket
      if delivery_undecided?(ticket)
        section(:ticket, :needs_decision, DELIVERY_UNDECIDED_MESSAGE)
      else
        section(:ticket, :decided, "Claimed: #{ticket.type_label}.")
      end
    elsif all_tickets_banked?
      section(:ticket, :decided, "All tickets banked for a future year.")
    else
      qualified = regular.count(&:is_qualified?)
      section(:ticket, :needs_decision,
              "#{pluralize_count(qualified, "ticket")} waiting — claim or bank #{(qualified == 1) ? "it" : "them"}.")
    end
  end

  def gift_section_status
    gifts = package.gift_items
    return section(:gift, :not_applicable, "No Gift Ticket available.") if gifts.empty?

    qualified = gifts.count(&:is_qualified?)
    if qualified.positive?
      section(:gift, :needs_decision, "#{pluralize_count(qualified, "Gift Ticket")} ready to claim.", optional: true)
    else
      section(:gift, :decided, "#{pluralize_count(gifts.count, "Gift Ticket")} claimed.")
    end
  end

  def vehicle_pass_section_status
    if using_vehicle_pass?
      section(:vehicle_pass, :decided, "Vehicle Pass claimed.")
    elsif vehicle_pass_doc.nil?
      section(:vehicle_pass, :not_applicable, "No Vehicle Pass available.")
    elsif ticket.nil?
      section(:vehicle_pass, :locked, "Claim a ticket first to unlock your Vehicle Pass.")
    else
      section(:vehicle_pass, :needs_decision, "Vehicle Pass available — claim it or skip it.", optional: true)
    end
  end

  def provisions_section_status
    return section(:provisions, :not_applicable, "No provisions earned.") if package.provisions.nil?

    if package.provisions_banked
      section(:provisions, :decided, "Provisions banked for a future year.")
    elsif !package.provisions_bankable
      section(:provisions, :decided, "Provisions are included automatically this year.")
    elsif provisions_undecided?
      section(:provisions, :needs_decision, "Choose to use or bank your provisions.", optional: true)
    else
      section(:provisions, :decided, "Provisions claimed for this year.")
    end
  end

  def sap_section_status
    return section(:sap, :decided, "Setup Access Pass claimed.") if using_sap?

    if sap_available?
      section(:sap, :needs_decision, "Claim your Setup Access Pass for early entry.", optional: true)
    else
      section(:sap, :not_applicable, "No Setup Access Pass available.")
    end
  end

  def sap_so_section_status
    if sap_so_list.any?
      section(:sap_so, :decided,
              "#{pluralize_count(sap_so_list.count, "significant other pass")} claimed.", optional: true)
    elsif ticketing_info.sap_so_max.to_i.positive?
      section(:sap_so, :needs_decision, "Optional — add passes for significant others.", optional: true)
    else
      section(:sap_so, :not_applicable, "Significant other passes not available.")
    end
  end

  # --- Section helpers -----------------------------------------------------

  def section(key, state, summary, optional: false)
    SectionStatus.new(key: key, state: state, summary: summary, optional: optional)
  end

  # An in-use, mailable deliverable with no delivery method chosen. A live
  # state, not just legacy data: update_status still accepts a claim without a
  # delivery_method, and banking always resets the method.
  def delivery_undecided?(item)
    item.present? && item.is_using? && item.delivery_none? && !using_staff_credential?
  end

  def sap_available?
    package.access_documents.any? do |ad|
      [AccessDocument::SAP, AccessDocument::STAFF_CREDENTIAL].include?(ad.type) && ad.available?
    end || have_staff_credential?
  end

  def provisions_undecided?
    package.provision_records.any? do |p|
      !p.is_allocated && p.status == Provision::AVAILABLE
    end
  end

  def delivery_label(document)
    case document.delivery_method
    when AccessDocument::DELIVERY_WILL_CALL then "Will Call pickup"
    when AccessDocument::DELIVERY_POSTAL then "USPS Standard Mail"
    when AccessDocument::DELIVERY_PRIORITY then "USPS Priority Mail"
    else "not chosen yet"
    end
  end

  def pluralize_count(count, singular)
    "#{count} #{singular.pluralize(count)}"
  end
end
