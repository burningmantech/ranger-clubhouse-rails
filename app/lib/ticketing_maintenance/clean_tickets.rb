# frozen_string_literal: true

module TicketingMaintenance
  # Post-event cleanup: submitted documents were turned in and become used;
  # qualified single-event documents (vehicle passes, SAPs, gift and LSD
  # tickets) become expired. Qualified SPTs and Staff Credentials roll over
  # untouched. Port of the Laravel
  # AccessDocumentController#cleanAccessDocsFromPriorEvent.
  class CleanTickets < Base
    def self.title = "Clean Tickets From Prior Event"

    def self.description
      "Mark all submitted documents as used, and expire unclaimed single-event documents " \
        "(Vehicle Passes, SAPs, gift and LSD tickets). Qualified SPTs and Staff Credentials are left alone."
    end

    # Selects exactly what changes, unlike upstream which walked every
    # submitted-or-qualified row and skipped the keepers one at a time.
    def self.scope
      base = AccessDocument.all
      base.where(status: AccessDocument::SUBMITTED)
          .or(base.where(status: AccessDocument::QUALIFIED, type: AccessDocument::EXPIRE_THIS_YEAR_TYPES))
    end

    def execute
      walk do |document|
        new_status = document.status == AccessDocument::SUBMITTED ? AccessDocument::USED : AccessDocument::EXPIRED
        status_row(document, to: new_status,
                   comment: "marked as #{new_status} via maintenance function",
                   audit_reason: "marked as #{new_status} via maintenance function")
      end
    end
  end
end
