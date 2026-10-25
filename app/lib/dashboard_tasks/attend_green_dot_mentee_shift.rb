# frozen_string_literal: true

module DashboardTasks
  class AttendGreenDotMenteeShift < DashboardTask
    def self.title
      "Attend & Pass a Green Dot Mentee Shift"
    end

    def self.skip_period
      [POST_EVENT, AFTER_EVENT]
    end

    def self.check(facts)
      arts = facts.art_trainings
      gd = arts.find { |a| a.is_green_dot_mentee }

      return skip_task if !gd || !gd.mentee_slot

      waiting(partial: "attend_green_dot_mentee_shift_waiting")
    end
  end
end
