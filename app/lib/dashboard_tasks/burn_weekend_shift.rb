# frozen_string_literal: true

module DashboardTasks
  class BurnWeekendShift < DashboardTask
    def self.title
      "Sign Up for a Burn Weekend Shift (Highly Recommended)"
    end

    def self.skip_period
      [POST_EVENT, AFTER_EVENT]
    end

    def self.check(facts)
      if facts.burn_weekend_signup
        return completed(partial: "burn_weekend_shift_completed")
      end

      if facts.burn_weekend_available
        return action_needed(partial: "burn_weekend_shift_needed")
      end

      skip_task
    end
  end
end
