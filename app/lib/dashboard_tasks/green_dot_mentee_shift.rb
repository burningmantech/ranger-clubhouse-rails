# frozen_string_literal: true

module DashboardTasks
  class GreenDotMenteeShift < DashboardTask
    def self.title
      "Sign Up for a Green Dot Mentee Shift"
    end

    def self.skip_period
      [POST_EVENT, AFTER_EVENT]
    end

    def self.check(facts)
      gd = facts.art_trainings.find { |a| a.is_green_dot_mentee }

      return skip_task unless gd
      return completed_task if gd.mentee_slot

      action_needed(partial: "green_dot_mentee_shift_needed")
    end
  end
end
