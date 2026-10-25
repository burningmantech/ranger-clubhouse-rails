# frozen_string_literal: true

module DashboardTasks
  class SignMotorPoolProtocol < DashboardTask
    def self.title
      "Sign the Ranger Vehicle Use Protocol"
    end

    def self.skip_period
      [POST_EVENT, AFTER_EVENT]
    end

    def self.check(facts)
      mvr_eligible = facts.mvr_eligible

      return skip_task unless facts.motorpool_agreement_available
      return completed_task if facts.motorpool_agreement_signed

      if facts.is_applicant && facts.training&.status != Training::PASS
        return not_available(partial: "sign_motor_pool_protocol_blocked")
      end

      if mvr_eligible
        action_needed(partial: "sign_motor_pool_protocol_needed")
      else
        optional(partial: "sign_motor_pool_protocol_needed")
      end
    end
  end
end
