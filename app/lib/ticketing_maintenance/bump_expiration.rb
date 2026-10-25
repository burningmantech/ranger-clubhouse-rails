# frozen_string_literal: true

module TicketingMaintenance
  # Add one year to the expiration date of every banked or qualified SPT and
  # Staff Credential. Port of the Laravel AccessDocumentController#bumpExpiration.
  #
  # Only those two types on purpose: the single-event types would have the bump
  # silently reverted by the model's expire-this-year callback, and documents
  # without an expiry date have nothing to bump. The operator's reason is
  # required here (upstream's UI required it too) and lands in both the comment
  # trail and the audit log.
  class BumpExpiration < Base
    def self.title = "Bump Expiration Dates"

    def self.description
      "Add one year to the expiration date on all banked and qualified SPTs and Staff Credentials. " \
        "A reason is required."
    end

    def self.reason_prompt
      "Why the dates are being bumped. Recorded on every record's audit trail."
    end

    def self.scope
      AccessDocument.where(status: [AccessDocument::BANKED, AccessDocument::QUALIFIED],
                           type: AccessDocument::REGULAR_TICKET_TYPES)
                    .where.not(expiry_date: nil)
    end

    def execute
      walk do |document|
        bumped = document.expiry_date + 1.year
        change = "expires #{document.expiry_date} → #{bumped}"
        document.expiry_date = bumped
        save_row(document, change:, comment: reason, audit_reason: reason)
      end
    end
  end
end
