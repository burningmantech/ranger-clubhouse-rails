# frozen_string_literal: true

module DashboardTasks
  class UploadPhoto < DashboardTask
    def self.title
      "Upload a BMID Photo"
    end

    def self.immediate
      true
    end

    def self.check(facts)
      photo = facts.photo
      case photo.photo_status
      when PersonPhoto::REJECTED
        urgent(partial: "upload_photo_rejected", immediate: true)
      when PersonPhoto::MISSING
        if !photo.upload_enabled
          waiting(partial: "upload_photo_disabled")
        else
          action_needed(partial: "upload_photo_action")
        end
      when PersonPhoto::SUBMITTED, PersonPhoto::APPROVED
        facts.is_applicant ? completed_task : skip_task
      else
        not_available(partial: "upload_photo_error")
      end
    end
  end
end
