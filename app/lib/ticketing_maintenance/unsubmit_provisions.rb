# frozen_string_literal: true

module TicketingMaintenance
  # Return the chosen people's earned claimed/submitted provisions to
  # available. Port of the Laravel ProvisionMaintenance.unsubmitProvisions.
  #
  # Not in the GROUPS registry, and deliberately NOT named execute: the
  # un-submit page's checkbox table (fed by UnsubmitProvisionsReport) is the
  # review step, so this always commits, for the people the operator picked.
  # It subclasses Base only for the shared ledger plumbing.
  class UnsubmitProvisions < Base
    # Mirrors UnsubmitProvisionsReport::CONSUMABLE_STATUSES; promote both to a
    # Provision constant when model changes are back on the table.
    CONSUMED_STATUSES = [Provision::CLAIMED, Provision::SUBMITTED].freeze

    def self.unsubmit(person_ids)
      new(commit: true).unsubmit(person_ids)
    end

    def unsubmit(person_ids)
      walk(Provision.where(person_id: person_ids, status: CONSUMED_STATUSES,
                           is_allocated: false)) do |provision|
        status_row(provision, to: Provision::AVAILABLE,
                   comment: "un-submit maintenance function",
                   audit_reason: "un-submit maintenance function")
      end
    end
  end
end
