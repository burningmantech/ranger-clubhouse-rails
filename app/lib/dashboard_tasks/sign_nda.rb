# frozen_string_literal: true

module DashboardTasks
  class SignNda < DashboardTask
    def self.title
      "Sign the Sensitive Data Access and Use Policy Agreement"
    end

    def self.immediate
      true
    end

    def self.check(facts)
      return skip_task unless facts.nda_required

      urgent(partial: "sign_nda_needed")
    end
  end
end
