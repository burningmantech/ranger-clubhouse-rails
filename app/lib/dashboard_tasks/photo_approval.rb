# frozen_string_literal: true

module DashboardTasks
  class PhotoApproval < DashboardTask
    def self.title
      "Photo Approval"
    end

    def self.check(facts)
      case facts.photo&.photo_status
      when PersonPhoto::APPROVED
        facts.is_applicant ? completed_task : skip_task
      when PersonPhoto::SUBMITTED
        waiting(partial: "photo_approval_review")
      when PersonPhoto::MISSING
        if facts.is_applicant
          not_available(partial: "photo_approval_missing")
        else
          skip_task
        end
      else
        skip_task
      end
    end
  end
end
