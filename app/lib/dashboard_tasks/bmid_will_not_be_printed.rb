# frozen_string_literal: true

module DashboardTasks
  class BmidWillNotBePrinted < DashboardTask
    def self.title
      "BMID Will Not Be Printed"
    end

    def self.skip_period
      [POST_EVENT, AFTER_EVENT]
    end

    def self.immediate
      true
    end

    def self.check(facts)
      month = facts.now.month

      # Don't bother if the month is neither July or August.
      return skip_task unless month == 7 || month == 8

      return skip_task if facts.bmid_qualified

      urgent(partial: "bmid_will_not_be_printed")
    end
  end
end
