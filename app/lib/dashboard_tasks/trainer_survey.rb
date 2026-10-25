# frozen_string_literal: true

module DashboardTasks
  class TrainerSurvey < DashboardTask
    def self.title
      "Take a Trainer's Training Survey (Optional)"
    end

    def self.skip_period
      [AFTER_EVENT]
    end

    def self.check(facts)
      if facts.surveys.trainers.present?
        optional(partial: "trainer_survey")
      else
        skip_task
      end
    end
  end
end
