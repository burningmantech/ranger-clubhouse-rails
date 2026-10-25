# frozen_string_literal: true

module DashboardTasks
  class SignBehavioralAgreement < DashboardTask
    def self.title
      "Sign the Burning Man Behavioral Standards Agreement (Optional)"
    end

    def self.skip_period
      [POST_EVENT, AFTER_EVENT]
    end

    def self.check(facts)
      return (facts.is_applicant ? completed_task : skip_task) if facts.behavioral_agreement

      optional(partial: "sign_behavioral_agreement_optional")
    end
  end
end
