# frozen_string_literal: true

# Tells the photo reviewers that people are waiting on them.
class PhotoPendingJob < ApplicationJob
  def perform
    pending = PersonPhoto.find_all_submitted
    return if pending.empty?

    PhotoPendingMailer.notify(pending_photos: pending).deliver_now
  end
end
