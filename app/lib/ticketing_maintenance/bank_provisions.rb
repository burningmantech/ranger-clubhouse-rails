# frozen_string_literal: true

module TicketingMaintenance
  # Post-event: carry earned available provisions forward as banked -- except
  # event radios, which expire unclaimed (Clean Provisions already consumed the
  # ones backed by attendance). Run AFTER Clean Provisions. Port of the Laravel
  # ProvisionMaintenance.bankProvisions.
  class BankProvisions < Base
    def self.title = "Bank Provisions From Prior Event"

    def self.description
      "Mark earned available provisions as banked. Unclaimed event radios are expired instead. " \
        "Only run AFTER Clean Provisions so event radios are properly handled."
    end

    def self.scope = Provision.where(status: Provision::AVAILABLE, is_allocated: false)

    def execute
      walk do |provision|
        if provision.type == Provision::EVENT_RADIO
          status_row(provision, to: Provision::EXPIRED, detail: "unclaimed event radio",
                     comment: "unclaimed event radio marked as expired via bank maintenance function",
                     audit_reason: "maintenance - bank provisions")
        else
          status_row(provision, to: Provision::BANKED,
                     comment: "marked as banked via bank maintenance function",
                     audit_reason: "maintenance - bank provisions")
        end
      end
    end
  end
end
