# frozen_string_literal: true

module DashboardTasks
  class TakeAlphaSurvey < DashboardTask
    def self.title
      "Take a Mentor Survey (Optional)"
    end

    def self.skip_period
      [AFTER_EVENT]
    end

    def self.check(facts)
      if facts.surveys.alpha_survey
        optional(partial: "take_alpha_survey")
      else
        skip_task
      end
    end
  end
end
