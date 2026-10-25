# frozen_string_literal: true

module DashboardTasks
  class TroubleshooterMentorSurvey < DashboardTask
    def self.title
      "Fill Out a Troubleshooter Mentor Survey"
    end

    def self.period
      [DURING_EVENT, POST_EVENT]
    end

    def self.check(facts)
      return skip_task unless facts.ts_mentor_worked

      action_needed(partial: "troubleshooter_mentor_survey")
    end
  end
end
