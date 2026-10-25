# frozen_string_literal: true

module DashboardTasks
  class AttendTraining < DashboardTask
    def self.title
      "Attend In-Person Training"
    end

    def self.skip_period
      [POST_EVENT, AFTER_EVENT]
    end

    def self.check(facts)
      if !facts.online_course_passed || facts.training&.status == Training::NO_SHIFT
        if facts.is_applicant || facts.is_auditor
          return not_available(partial: "attend_training_signup")
        end

        return skip_task
      end

      training = facts.training
      case training.status
      when Training::PASS
        if facts.is_cheetah_cub
          completed(partial: "attend_training_cheetah")
        else
          return completed_task if facts.is_applicant || facts.is_auditor
          completed(partial: "attend_training_art")
        end
      when Training::NO_SHOW
        urgent(partial: "attend_training_no_show", immediate: true)
      when Training::FAIL
        urgent(partial: "attend_training_fail", immediate: true)
      when Training::PENDING
        action_needed(partial: "attend_training_pending")
      else
        skip_task
      end
    end
  end
end
