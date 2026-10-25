# frozen_string_literal: true

module DashboardTasks
  class SignUpForTraining < DashboardTask
    def self.title
      "Sign Up for In-Person Training"
    end

    def self.skip_period
      [POST_EVENT, AFTER_EVENT]
    end

    def self.check(facts)
      return completed_task if facts.training.status != Training::NO_SHIFT

      unless facts.online_course_passed
        return not_available(partial: "sign_up_for_training_blocked")
      end

      if facts.trainings_available
        action_needed(partial: "sign_up_for_training_needed")
      else
        waiting(partial: "sign_up_for_training_waiting")
      end
    end
  end
end
