# frozen_string_literal: true

module TicketingMaintenance
  # Expire every live document whose expiry date has passed. Port of the
  # Laravel AccessDocumentController#expireAccessDocuments. Emails are shown so
  # the operator can tell people their ticket lapsed.
  class ExpireTickets < Base
    def self.title = "Expire Tickets"

    def self.description
      "Mark banked, claimed, or qualified documents whose expiration date has passed as expired."
    end

    def self.show_email? = true

    # expiry_date is a date column; upstream's strict compare against the
    # current timestamp includes today, so on-or-before-today matches it.
    def self.scope
      AccessDocument.where(status: AccessDocument::ACTIVE_STATUSES, expiry_date: ..Date.current)
    end

    def execute
      walk do |document|
        status_row(document, to: AccessDocument::EXPIRED,
                   detail: "expiry date #{document.expiry_date}",
                   comment: "marked as expired via maintenance function",
                   audit_reason: "marked as expired via maintenance function")
      end
    end
  end
end
