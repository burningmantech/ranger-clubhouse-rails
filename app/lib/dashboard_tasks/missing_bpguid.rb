# frozen_string_literal: true

module DashboardTasks
  class MissingBpguid < DashboardTask
    def self.title
      "Link Your Burner Profile"
    end

    def self.immediate
      true
    end

    def self.check(facts)
      if facts.missing_bpguid
        urgent(partial: "missing_bpguid")
      else
        skip_task
      end
    end
  end
end
