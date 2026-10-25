# frozen_string_literal: true

module DashboardTasks
  class TicketingClosed < DashboardTask
    def self.title
      "Ticketing Has Closed"
    end

    def self.period
      [BEFORE_EVENT]
    end

    def self.check(facts)
      return skip_task if facts.ticketing_period != "closed" || !facts.ticketing_package

      completed(
        partial: "dashboard_tickets",
        payload: DashboardTaskResult::Payload.new(
          tickets: TicketHelper.build_tickets(facts),
          ticketing_open: false
        )
      )
    end
  end
end
