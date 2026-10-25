# frozen_string_literal: true

module DashboardTasks
  class SignRadioCheckoutAgreement < DashboardTask
    def self.title
      "Sign the Ranger Equipment Checkout Agreement"
    end

    def self.skip_period
      [POST_EVENT, AFTER_EVENT]
    end

    def self.check(facts)
      return completed_task if facts.asset_authorized

      if facts.is_applicant && facts.training&.status != Training::PASS
        return not_available(partial: "sign_radio_checkout_agreement_blocked")
      end

      unless facts.radio_checkout_agreement_enabled
        if facts.is_applicant
          return not_available(partial: "sign_radio_checkout_agreement_not_available")
        end

        return skip_task
      end

      is_august = facts.now.month == 8
      if is_august
        urgent(partial: "sign_radio_checkout_agreement_needed", immediate: true)
      else
        action_needed(partial: "sign_radio_checkout_agreement_needed")
      end
    end
  end
end
