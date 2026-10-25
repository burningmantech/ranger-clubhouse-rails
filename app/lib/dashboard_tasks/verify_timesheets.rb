# frozen_string_literal: true

module DashboardTasks
  class VerifyTimesheets < DashboardTask
    def self.title
      "Verify Timesheet Entries and Confirm Entire Timesheet as Final (If Done Rangering)"
    end

    def self.immediate
      true
    end

    def self.skip_period
      [BEFORE_EVENT, AFTER_EVENT]
    end

    def self.check(facts)
      if !facts.did_work || (!facts.timesheets_unverified && facts.timesheet_confirmed)
        return (facts.did_work && facts.timesheet_confirmed) ? completed_task : skip_task
      end

      action_needed(partial: "verify_timesheets")
    end
  end
end
