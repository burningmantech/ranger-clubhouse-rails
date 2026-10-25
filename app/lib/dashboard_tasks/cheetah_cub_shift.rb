# frozen_string_literal: true

module DashboardTasks
  class CheetahCubShift < DashboardTask
    def self.title
      "Contact the Mentors to Sign Up for a Cheetah Cub Shift"
    end

    def self.skip_period
      [POST_EVENT, AFTER_EVENT]
    end

    def self.check(facts)
      return skip_task unless facts.is_cheetah_cub
      return completed_task if facts.cheetah_cub_shift

      if facts.online_course_passed
        urgent(partial: "cheetah_cub_shift_needed")
      else
        action_needed(partial: "cheetah_cub_shift_needed")
      end
    end
  end
end
