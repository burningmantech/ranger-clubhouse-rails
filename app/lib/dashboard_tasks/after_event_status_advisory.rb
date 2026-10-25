# frozen_string_literal: true

module DashboardTasks
  class AfterEventStatusAdvisory < DashboardTask
    def self.check(facts)
      status = facts.status
      return skip_task unless [Person::RETIRED, Person::INACTIVE, Person::INACTIVE_EXTENSION].include?(status)

      note(partial: "after_event_status_advisory")
    end
  end
end
