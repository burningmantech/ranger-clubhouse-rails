# frozen_string_literal: true

module DashboardTasks
  class ArtTraining < DashboardTask
    def self.title
      "Sign Up for & Attend Advanced Ranger Training (ART)"
    end

    def self.skip_period
      [POST_EVENT, AFTER_EVENT]
    end

    def self.check(facts)
      arts = facts.art_trainings
      if arts.empty? || !facts.online_course_enabled || !facts.trainings_available
        return skip_task
      end

      result = if arts.any? { |a| [Training::NO_SHOW, Training::FAIL].include?(a.status) }
                 STATUS_URGENT
               elsif arts.any? { |a| a.status == Training::NO_SHIFT }
                 STATUS_ACTION_NEEDED
               elsif arts.any? { |a| a.status == Training::PENDING }
                 STATUS_WAITING
               else
                 STATUS_COMPLETED
               end

      DashboardTaskResult.new(result:, partial: "dashboard_arts")
    end
  end
end
