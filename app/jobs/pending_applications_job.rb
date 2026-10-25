# frozen_string_literal: true

# Reminds the Volunteer Coordinators that approved applications are waiting to
# be turned into Clubhouse accounts.
class PendingApplicationsJob < ApplicationJob
  def perform
    applications = ProspectiveApplication.retrieve_approved
    return if applications.empty?

    ProspectiveApplication::ApprovedReminderMailer.notify(applications:).deliver_now
  end
end
