# frozen_string_literal: true

module DashboardTasks
  class SandmanAffidavit < DashboardTask
    def self.title
      "Sign the Sandman Affidavit"
    end

    def self.skip_period
      [POST_EVENT, AFTER_EVENT]
    end

    def self.check(facts)
      return completed_task if facts.sandman_affidavit_signed

      if facts.sandman_affidavit_required
        urgent(partial: "sandman_affidavit_needed", immediate: true)
      else
        skip_task
      end
    end
  end
end
