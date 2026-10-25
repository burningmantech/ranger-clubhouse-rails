# frozen_string_literal: true

module TicketingMaintenance
  # Return every banked provision to available before ticketing opens.
  # Port of the Laravel ProvisionMaintenance.unbankProvisions.
  class UnbankProvisions < Base
    def self.title = "Unbank Provisions"

    def self.description
      "Take all banked provisions and update the status to available. Do this before ticketing is opened."
    end

    def self.scope = Provision.where(status: Provision::BANKED)

    def execute
      walk do |provision|
        status_row(provision, to: Provision::AVAILABLE,
                   comment: "marked as available via maintenance function",
                   audit_reason: "maintenance - unbank provisions")
      end
    end
  end
end
