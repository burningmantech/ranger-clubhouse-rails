# frozen_string_literal: true

module TicketingMaintenance
  # Expire every earned live provision whose expiration date has passed.
  # Allocated provisions are excluded -- they live and die with their event via
  # Clean Provisions. Port of the Laravel ProvisionMaintenance.expire. Emails
  # are shown so the operator can tell people their provisions lapsed.
  class ExpireProvisions < Base
    def self.title = "Expire Provisions"

    def self.description
      "Mark banked, claimed, or available earned provisions whose expiration date has passed as expired."
    end

    def self.show_email? = true

    def self.scope
      Provision.where(status: Provision::ACTIVE_STATUSES, is_allocated: false,
                      expires_on: ..Date.current)
    end

    def execute
      walk do |provision|
        status_row(provision, to: Provision::EXPIRED,
                   detail: "expiry date #{provision.expires_on}",
                   comment: "marked as expired via maintenance function",
                   audit_reason: "marked as expired via maintenance function")
      end
    end
  end
end
