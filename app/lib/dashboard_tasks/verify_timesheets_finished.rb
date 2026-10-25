# frozen_string_literal: true

module DashboardTasks
  class VerifyTimesheetsFinished < DashboardTask
    def self.title
      "Verify Timesheet Entries and Confirm Entire Timesheet as Correct"
    end

    def self.skip_period
      [AFTER_EVENT, BEFORE_EVENT]
    end

    def self.check(facts)
      if !facts.did_work || facts.timesheets_unverified || !facts.timesheet_confirmed
        return skip_task
      end

      completed(partial: "verify_timesheets_finished")
    end
  end
end
