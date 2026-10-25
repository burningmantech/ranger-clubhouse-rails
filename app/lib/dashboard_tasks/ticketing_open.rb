# frozen_string_literal: true

module DashboardTasks
  class TicketingOpen < DashboardTask
    def self.title
      "Claim Tickets, Vehicle Passes, and Setup Access Passes"
    end

    def self.skip_period
      [POST_EVENT, AFTER_EVENT]
    end

    def self.check(facts)
      return skip_task if facts.ticketing_period != "open" || !facts.ticketing_package

      tickets = TicketHelper.build_tickets(facts)
      if tickets.qualified_count > 0 || tickets.not_finished
        action_needed(
          partial: "dashboard_tickets",
          immediate: true,
          payload: DashboardTaskResult::Payload.new(tickets:)
        )
      else
        completed(
          partial: "dashboard_tickets",
          payload: DashboardTaskResult::Payload.new(tickets:, ticketing_open: true)
        )
      end
    end
  end
end
