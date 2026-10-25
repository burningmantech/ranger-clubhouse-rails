# frozen_string_literal: true

module DashboardTasks
  class OnlineCourse < DashboardTask
    def self.title
      "Read the Ranger Manual & Complete the Online Course"
    end

    def self.skip_period
      [POST_EVENT, AFTER_EVENT]
    end

    def self.check(facts)
      if facts.online_course_passed
        return completed(partial: "online_course_completed")
      end

      unless facts.online_course_enabled
        return waiting(partial: "online_course_waiting")
      end

      if facts.is_applicant && !facts.prev_completed
        return not_available(partial: "online_course_blocked")
      end

      if facts.is_echelon
        optional(partial: "online_course_needed")
      else
        action_needed(partial: "online_course_needed")
      end
    end
  end
end
