# frozen_string_literal: true

module DashboardTasks
  class AttendAlphaShift < DashboardTask
    def self.title
      "Attend Your Alpha Shift"
    end

    def self.check(facts)
      if [Person::BONKED, Person::UBERBONKED].include?(facts.status)
        return blocked(partial: "attend_alpha_shift_bonked")
      end

      if facts.alpha_shift
        if facts.alpha_shift[:status] == Training::PENDING
          return action_needed(partial: "attend_alpha_shift_pending")
        else
          return urgent(partial: "attend_alpha_shift_missed")
        end
      end

      return not_available(partial: "attend_alpha_shift_not_available") unless facts.alpha_shifts_available

      not_available(partial: "attend_alpha_shift_sign_up")
    end
  end
end
