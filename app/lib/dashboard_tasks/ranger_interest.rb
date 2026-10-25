# frozen_string_literal: true

module DashboardTasks
  class RangerInterest < DashboardTask
    def self.title
      "Becoming a Black Rock Ranger"
    end

    def self.check(facts)
      action_needed(
        partial: "ranger_interest_signup",
        payload: DashboardTaskResult::Payload.new(year: facts.now.year + 1)
      )
    end
  end
end
