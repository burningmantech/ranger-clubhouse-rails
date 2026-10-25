# frozen_string_literal: true

module DashboardTasks
  class SignUpForAlphaShift < DashboardTask
    ALPHA_SHIFT_DISCLAIMER = "Alpha shifts are ONLY available Saturday (the day before the gate opens), Sunday, Monday, and Tuesday. No shifts are offered later in the week."

    def self.title
      "Sign Up for an Alpha Shift"
    end

    def self.check(facts)
      return skip_task if facts.is_any_bonked
      return completed_task if facts.alpha_shift

      if facts.training&.status != Training::PASS
        return not_available(partial: "sign_up_for_alpha_shift_blocked")
      end

      if facts.status != Person::PROSPECTIVE && facts.alpha_shifts_available
        action_needed(partial: "sign_up_for_alpha_shift_needed")
      else
        waiting(partial: "sign_up_for_alpha_shift_waiting")
      end
    end
  end
end
