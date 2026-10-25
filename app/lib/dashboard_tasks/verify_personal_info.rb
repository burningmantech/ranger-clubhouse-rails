# frozen_string_literal: true

module DashboardTasks
  class VerifyPersonalInfo < DashboardTask
    def self.title
      "Review and Update Personal Information"
    end

    def self.skip_period
      [POST_EVENT, AFTER_EVENT]
    end

    def self.check(facts)
      return completed_task if facts.has_reviewed_pi

      if !facts.is_applicant && !facts.is_echelon && facts.online_course_passed
        urgent(partial: "verify_personal_info", immediate: true)
      else
        action_needed(partial: "verify_personal_info")
      end
    end
  end
end
