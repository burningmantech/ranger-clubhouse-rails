# frozen_string_literal: true

module DashboardTasks
  class AttendCheetahCubShift < DashboardTask
    def self.title
      "Attend Your Cheetah Cub Shift"
    end

    def self.skip_period
      [POST_EVENT, AFTER_EVENT]
    end

    def self.check(facts)
      return skip_task unless facts.is_cheetah_cub

      signup = facts.cheetah_cub_shift
      if signup && signup["status"] == "pending"
        action_needed(partial: "attend_cheetah_cub_shift_pending")
      else
        skip_task
      end
    end
  end
end
