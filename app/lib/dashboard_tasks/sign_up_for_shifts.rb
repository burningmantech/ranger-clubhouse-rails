# frozen_string_literal: true

module DashboardTasks
  class SignUpForShifts < DashboardTask
    def self.title
      "Sign Up for Shifts"
    end

    def self.skip_period
      [POST_EVENT, AFTER_EVENT]
    end

    def self.check(facts)
      if !facts.online_course_passed && (facts.is_auditor || facts.is_applicant)
        return not_available(partial: "sign_up_for_shifts_blocked")
      end

      if !facts.dirt_shifts_available && !facts.is_echelon
        return not_available(partial: "sign_up_for_shifts_schedule_pending")
      end

      shift_signups = facts.shift_signups
      if shift_signups.slot_count > 0
        completed(partial: "sign_up_for_shifts_completed", sticky: true)
      else
        action_needed(partial: "sign_up_for_shifts_needed")
      end
    end
  end
end
