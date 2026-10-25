# frozen_string_literal: true

module DashboardTasks
  class TakeStudentSurvey < DashboardTask
    def self.title
      "Take a Training Survey (Optional)"
    end

    def self.skip_period
      [AFTER_EVENT]
    end

    def self.check(facts)
      return skip_task unless facts.surveys.sessions.present?

      optional(partial: "take_student_survey")
    end
  end
end
