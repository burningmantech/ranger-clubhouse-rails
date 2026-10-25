# frozen_string_literal: true

require "test_helper"

class ProspectiveApplicationStatusMailTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  setup do
    travel_to Time.zone.local(2026, 4, 16, 12, 0, 0)
    Current.reset
    Current.person = person(:auditor_ranger)
    @application = prospective_application(:pending_qualified)
    ActionMailer::Base.deliveries.clear
  end

  teardown do
    Current.reset
    travel_back
    ActionMailer::Base.deliveries.clear
  end

  test "every email-sending status has a mailer" do
    assert_equal ProspectiveApplication::STATUSES_THAT_SEND_EMAIL.sort,
                 ProspectiveApplicationStatusMail::STATUS_TO_MAILER.keys.sort
  end

  test "execute is a no-op for statuses without email" do
    assert_no_difference ["MailLog.count", "ActionMailer::Base.deliveries.size"] do
      ProspectiveApplicationStatusMail.execute(@application, ProspectiveApplication::STATUS_HANDLE_CHECK)
    end
  end

  test "execute delivers the mail and records the mail log and audit trail" do
    assert_difference ["MailLog.count", "ActionMailer::Base.deliveries.size"], 1 do
      ProspectiveApplicationStatusMail.execute(@application, ProspectiveApplication::STATUS_HOLD_AGE_ISSUE)
    end

    mail = ActionMailer::Base.deliveries.last
    assert_equal "Hey Alice, we have a question regarding your Ranger application", mail.subject
    assert_equal ["alice.applicant@example.com"], mail.to

    log = MailLog.order(:created_at).last
    assert_equal @application.id, log.prospective_application_id
    assert_equal person(:auditor_ranger).id, log.sender_id
    assert log.message_id.present?
    assert log.was_sent

    audit = ProspectiveApplicationLog.where(prospective_application_id: @application.id).order(:created_at).last
    assert_equal "emailed", audit.action
    assert_equal mail.subject, audit.data["subject"]
  end

  test "sandbox setting redirects applicant email" do
    setting = Setting.find_or_initialize_by(name: Setting::PROSPECTIVE_APPLICATION_MAIL_SANDBOX)
    setting.update!(value: "sandbox@example.com")

    ProspectiveApplicationStatusMail.execute(@application, ProspectiveApplication::STATUS_HOLD_AGE_ISSUE)

    assert_equal ["sandbox@example.com"], ActionMailer::Base.deliveries.last.to
  ensure
    setting&.destroy
  end

  test "rrn-check goes to the RRN team, not the applicant" do
    setting = Setting.find_or_initialize_by(name: Setting::RRN_EMAIL)
    setting.update!(value: "rrn@example.com")

    ProspectiveApplicationStatusMail.execute(@application, ProspectiveApplication::STATUS_HOLD_RRN_CHECK)

    mail = ActionMailer::Base.deliveries.last
    assert_equal ["rrn@example.com"], mail.to
    assert_equal "A-#{@application.id} : Request for Regional Ranger Experience Validation", mail.subject
  ensure
    setting&.destroy
  end

  test "an rrn-check sent to two addresses is logged once per address" do
    setting = Setting.find_or_initialize_by(name: Setting::RRN_EMAIL)
    setting.update!(value: "rrn@example.com,rrn-lead@example.com")

    assert_difference({ "ActionMailer::Base.deliveries.size" => 1, "MailLog.count" => 2 }) do
      ProspectiveApplicationStatusMail.execute(@application, ProspectiveApplication::STATUS_HOLD_RRN_CHECK)
    end

    rows = MailLog.order(:id).last(2)
    assert_equal ["rrn@example.com", "rrn-lead@example.com"], rows.map(&:to_email)
    assert_equal [ActionMailer::Base.deliveries.last.message_id], rows.map(&:message_id).uniq
    assert_equal [@application.id], rows.map(&:prospective_application_id).uniq
  ensure
    setting&.destroy
  end

  # Through SES, the message deliver_now hands back carries the id SES gave
  # it, and the row has to keep that id: it is the one SES's delivery, bounce
  # and complaint reports name.
  test "an email sent through SES is logged under the id SES gave it" do
    sent = with_ses_delivery("0100018f2b6c1a2e-status-mail-000000") do
      ProspectiveApplicationStatusMail.execute(@application, ProspectiveApplication::STATUS_HOLD_AGE_ISSUE)
    end

    assert_equal 1, sent.size
    assert_equal ["alice.applicant@example.com"], sent.first[:destination][:to_addresses]
    assert_empty ActionMailer::Base.deliveries

    log = MailLog.order(:id).last
    assert_equal "0100018f2b6c1a2e-status-mail-000000", log.message_id
    assert_equal "alice.applicant@example.com", log.to_email
    assert_equal @application.id, log.prospective_application_id
  end

  test "preview renders the mail without sending" do
    html = nil
    assert_no_difference ["MailLog.count", "ActionMailer::Base.deliveries.size"] do
      html = ProspectiveApplicationStatusMail.preview(@application, ProspectiveApplication::STATUS_MORE_HANDLES, "Try again")
    end

    assert_includes html.downcase, "<!doctype html>"
    assert_includes html, "FIVE MORE HANDLES TO CONSIDER"
    assert_includes html, "Try again"
  end

  test "preview raises for statuses without an associated email" do
    assert_raises ArgumentError do
      ProspectiveApplicationStatusMail.preview(@application, ProspectiveApplication::STATUS_PENDING)
    end
  end

  private

  # Sends mail for one block through the gem's :ses_v2 delivery method -- the
  # one production's :ses_mail (SesMailDelivery) builds on, which sets the
  # same header -- to a stand-in SES that answers every SendEmail with
  # message_id. Returns what SES was asked to send.
  def with_ses_delivery(message_id)
    calls = []
    delivery_method = ActionMailer::Base.delivery_method
    settings = ActionMailer::Base.ses_v2_settings
    ActionMailer::Base.delivery_method = :ses_v2
    ActionMailer::Base.ses_v2_settings = {
      sesv2_client: Aws::SESV2::Client.new(stub_responses: {
                                             send_email: lambda do |context|
                                               calls << context.params
                                               { message_id: }
                                             end
                                           })
    }
    yield
    calls
  ensure
    ActionMailer::Base.delivery_method = delivery_method
    ActionMailer::Base.ses_v2_settings = settings
  end
end
