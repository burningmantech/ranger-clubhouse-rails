# frozen_string_literal: true

module DashboardTasks
  module TicketHelper
    module_function

    def build_tickets(facts)
      pkg = facts.ticketing_package
      return nil unless pkg

      claimed = pkg.access_documents.filter { |t| t.is_using? && t.regular_ticket? } +
                pkg.gift_items.filter(&:is_using?) +
                pkg.lsd_items.filter(&:is_using?)

      OpenStruct.new(
        claimed:,
        banked_count: pkg.access_documents.count(&:is_banked?),
        qualified_count: pkg.access_documents.count { |a| a.is_qualified? && a.regular_ticket? },
        not_critical_count: pkg.access_documents.count { |ad| ad.is_qualified? && [AccessDocument::SAP, AccessDocument::VEHICLE_PASS_SP].include?(ad.type) },
        provision_items: !pkg.provisions_banked ? pkg.provision_records : nil,
        not_finished: pkg.started_at && !pkg.finished_at
      ).freeze
    end
  end
end
