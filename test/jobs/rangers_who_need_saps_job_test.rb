# frozen_string_literal: true

require "test_helper"

class RangersWhoNeedSapsJobTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  setup do
    ActionMailer::Base.deliveries.clear
  end

  test "perform mails the report to the ticketing address" do
    set_report_email("ticketing@example.com")

    assert_emails 1 do
      RangersWhoNeedSapsJob.perform_now
    end

    mail = ActionMailer::Base.deliveries.last

    assert_equal ["ticketing@example.com"], mail.to
    assert_match "Ranger SAP Candidates", mail.subject
  end

  test "perform sends nothing when no address is set" do
    set_report_email("")

    assert_emails 0 do
      RangersWhoNeedSapsJob.perform_now
    end
  end

  private

  def set_report_email(address)
    Setting.find_or_initialize_by(name: Setting::TAS_SAP_REPORT_EMAIL).update!(value: address)
  end
end
