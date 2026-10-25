# frozen_string_literal: true

module TicketingMaintenance
  # Grant a Gift Vehicle Pass to Staff Credential holders and a Special Price
  # Vehicle Pass to Special Price Ticket holders who don't have one already.
  # People holding both ticket types receive both passes (one ledger row per
  # pass granted). Port of the Laravel GrantPasses.grantVehiclePasses.
  class GrantVps < GrantTask
    # Which held ticket earns which vehicle pass.
    PASSES = {
      AccessDocument::STAFF_CREDENTIAL => AccessDocument::VEHICLE_PASS_GIFT,
      AccessDocument::SPT => AccessDocument::VEHICLE_PASS_SP
    }.freeze

    # An already granted pass in any live pre-use status blocks a duplicate;
    # upstream's exact list, kept spelled out because vehicle passes never bank.
    HELD_VP_STATUSES = AccessDocument::AVAILABLE_STATUSES

    def self.title = "Grant Vehicle Passes"

    def self.description
      "Grant Gift Vehicle Passes to current Staff Credential holders and Special Price Vehicle Passes " \
        "to Special Price Ticket holders who don't have one already. People with both receive both."
    end

    # A banked ticket still earns a pass, hence ACTIVE_STATUSES.
    def self.recipients(ticket_type, vp_type)
      holder_ids = AccessDocument.where(type: ticket_type, status: AccessDocument::ACTIVE_STATUSES)
                                 .where.not(person_id: AccessDocument.where(type: vp_type, status: HELD_VP_STATUSES)
                                                                     .select(:person_id))
                                 .select(:person_id)

      Person.where(id: holder_ids)
            .where.not(status: TicketingManagement::EXCLUDED_HOLDER_STATUSES)
            .order(:callsign)
            .select(:id, :callsign, :status)
    end

    def execute
      PASSES.flat_map do |ticket_type, vp_type|
        granting(vp_type) do
          self.class.recipients(ticket_type, vp_type).map do |person|
            grant_row(person,
                      type: vp_type,
                      status: AccessDocument::QUALIFIED,
                      delivery_method: AccessDocument::DELIVERY_NONE)
          end
        end
      end
    end
  end
end
