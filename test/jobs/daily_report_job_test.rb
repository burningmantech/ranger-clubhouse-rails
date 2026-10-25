# frozen_string_literal: true

require "test_helper"

class DailyReportJobTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  setup do
    ActionMailer::Base.deliveries.clear
    ErrorLog.delete_all
    Broadcast.delete_all
    set_report_email("daily@example.com")
  end

  test "perform mails the report to the address it is configured with" do
    assert_emails 1 do
      DailyReportJob.perform_now
    end

    mail = ActionMailer::Base.deliveries.last

    assert_equal ["daily@example.com"], mail.to
    assert_match "Daily Report", mail.subject
  end

  test "perform sends nothing when no address is set" do
    set_report_email("")

    assert_emails 0 do
      DailyReportJob.perform_now
    end
  end

  # A report covering more than a day would repeat yesterday's errors every
  # morning until no one read it any more.
  test "the report carries only the last day of errors" do
    ErrorLog.create!(error_type: "recent-error", data: {}, created_at: 2.hours.ago)
    ErrorLog.create!(error_type: "old-error", data: {}).update_column(:created_at, 2.days.ago)

    DailyReportJob.perform_now
    body = ActionMailer::Base.deliveries.last.body.to_s

    assert_includes body, "recent-error"
    assert_not_includes body, "old-error"
  end

  test "a failed broadcast reports how many people it was meant for" do
    Broadcast.create!(alert_id: alert(:shift_muster).id, sender_id: person(:active_ranger).id,
                      subject: "Muster", sent_email: true, email_failed: 2, recipient_count: 987_654)

    DailyReportJob.perform_now
    body = ActionMailer::Base.deliveries.last.body.to_s

    assert_includes body, "Shift Muster"
    # A number no timestamp or count in the rest of the email could produce.
    assert_includes body, "987654"
  end

  test "a status change from yesterday is listed" do
    PersonStatus.create!(person: person(:active_ranger), person_source: person(:auditor_ranger),
                         old_status: Person::INACTIVE, new_status: Person::ACTIVE,
                         reason: "returned to rangering")

    DailyReportJob.perform_now
    body = ActionMailer::Base.deliveries.last.body.to_s

    assert_includes body, "returned to rangering"
  end

  private

  def set_report_email(address)
    Setting.find_or_initialize_by(name: Setting::DAILY_REPORT_EMAIL).update!(value: address)
  end
end
