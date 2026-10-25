# frozen_string_literal: true

require "test_helper"

class PendingApplicationsJobTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  setup do
    ActionMailer::Base.deliveries.clear
  end

  test "perform mails the coordinators about approved applications" do
    application = prospective_application(:approved_ready)

    assert_emails 1 do
      PendingApplicationsJob.perform_now
    end

    body = ActionMailer::Base.deliveries.last.body.to_s

    assert_includes body, "A-#{application.id}"
    assert_includes body, application.approved_handle
  end

  test "perform sends nothing when no application is approved" do
    ProspectiveApplication.retrieve_approved.update_all(status: ProspectiveApplication::STATUS_PENDING)

    assert_emails 0 do
      PendingApplicationsJob.perform_now
    end
  end
end
