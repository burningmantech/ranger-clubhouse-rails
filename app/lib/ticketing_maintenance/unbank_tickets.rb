# frozen_string_literal: true

module TicketingMaintenance
  # Return every banked ticket to qualified before ticketing opens.
  # Port of the Laravel AccessDocumentController#unbankAccessDocuments.
  class UnbankTickets < Base
    def self.title = "Unbank Tickets"

    def self.description
      "Take all banked tickets and update the status to qualified. Do this before ticketing is opened."
    end

    def self.scope = AccessDocument.where(status: AccessDocument::BANKED)

    def execute
      walk do |document|
        status_row(document, to: AccessDocument::QUALIFIED,
                   comment: "marked as qualified via maintenance function",
                   audit_reason: "maintenance - unbank items")
      end
    end
  end
end
