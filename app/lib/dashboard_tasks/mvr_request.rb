# frozen_string_literal: true

module DashboardTasks
  class MvrRequest < DashboardTask
    def self.title
      "Submit a MVR Request"
    end

    def self.period
      [BEFORE_EVENT, DURING_EVENT]
    end

    def self.check(facts)
      if !facts.motorpool_agreement_available || (!facts.mvr_eligible && !facts.mvr_potential)
        return skip_task
      end

      if facts.org_vehicle_insurance
        return completed(partial: "mvr_request_approved")
      end

      if facts.ignore_mvr
        return completed(partial: "mvr_request_muted")
      end

      action_needed(partial: "mvr_request_eligible")
    end
  end
end
