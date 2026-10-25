# frozen_string_literal: true

require "test_helper"

# Every ActionMailer email leaves out the addresses EmailSuppression holds.
class SuppressedRecipientsInterceptorTest < ActiveSupport::TestCase
  include EmailSuppressionTestHelper
  include EnvTestHelper
  include TrainingSlotTestHelper

  INBOX = "inbox@example.com"

  setup do
    Current.reset
    ActionMailer::Base.deliveries.clear
    @ranger = person(:active_ranger)
    @slot = create_slot(positions(:training_lead), begins: Time.zone.local(2026, 8, 20, 9, 0, 0))
  end

  teardown do
    Current.reset
  end

  # =========================================================================
  # Order
  # =========================================================================

  # Mail runs interceptors in the order they were registered.
  test "it runs first, ahead of the test address" do
    assert_equal SuppressedRecipientsInterceptor, Mail.delivery_interceptors.first
    assert_includes Mail.delivery_interceptors, MailTestAddressInterceptor
  end

  test "under the test address, the inbox gets the email once, naming only the live recipient" do
    suppress_email("dead@example.com")

    with_env(MailTestAddressInterceptor::ADDRESS_VAR => INBOX) do
      contacts_email("dead@example.com, live@example.com").deliver_now
    end

    sent = ActionMailer::Base.deliveries.sole
    assert_equal [INBOX], sent.to
    assert_equal "live@example.com", sent.header[MailTestAddressInterceptor::RECIPIENTS_HEADER].value
  end

  test "under the test address, an email with no live recipient reaches no inbox" do
    suppress_email("dead@example.com")

    with_env(MailTestAddressInterceptor::ADDRESS_VAR => INBOX) { contacts_email("dead@example.com").deliver_now }

    assert_empty ActionMailer::Base.deliveries
  end

  # =========================================================================
  # Dropping recipients
  # =========================================================================

  test "a suppressed To beside a live one: only the live one is left, and the skip is logged" do
    suppress_email(@ranger.email)

    assert_difference -> { ActionLog.where(event: "email-suppressed").count }, 1 do
      contacts_email("#{@ranger.email}, live@example.com").deliver_now
    end

    sent = ActionMailer::Base.deliveries.sole
    assert_equal ["live@example.com"], sent.to
    assert_equal ["live@example.com"], MailLog.where(subject: sent.subject).pluck(:to_email)

    log = ActionLog.find_by!(event: "email-suppressed")
    assert_nil log.person_id
    assert_equal @ranger.id, log.target_person_id
    # Never the body.
    assert_equal({ "to_email" => @ranger.email, "mailer" => "TrainingSessionFullMailer", "subject" => sent.subject },
                 log.data)
  end

  test "a suppressed Cc and Bcc are dropped, the others kept as written, and an empty field removed" do
    suppress_email("dead-cc@example.com")
    suppress_email("dead-bcc@example.com")
    message = contacts_email("live@example.com").message
    message.cc = ["Dead Cc <dead-cc@example.com>", "Live Cc <live-cc@example.com>"]
    message.bcc = "dead-bcc@example.com"

    SuppressedRecipientsInterceptor.delivering_email(message)

    assert_equal ["live@example.com"], message.to
    assert_equal "Live Cc <live-cc@example.com>", message[:cc].value
    assert_nil message.bcc
    assert_nil message.header[:bcc]
    assert message.perform_deliveries
    assert_equal %w[dead-bcc@example.com dead-cc@example.com],
                 ActionLog.where(event: "email-suppressed").map { it.data["to_email"] }.sort
  end

  test "every recipient suppressed: the email is held, and nothing is delivered or logged as mail" do
    suppress_email("dead@example.com")
    suppress_email("also-dead@example.com")
    delivery = contacts_email("dead@example.com, also-dead@example.com")
    delivery.message.cc = "dead@example.com"

    assert_no_difference "MailLog.count" do
      delivery.deliver_now
    end

    assert_not delivery.message.perform_deliveries
    assert_nil delivery.message.header[:to]
    assert_nil delivery.message.header[:cc]
    assert_empty ActionMailer::Base.deliveries
    assert_equal 2, ActionLog.where(event: "email-suppressed").count
  end

  test "a complaint row is skipped like a bounce row" do
    suppress_email("complained@example.com", reason: EmailSuppression::COMPLAINT)

    contacts_email("complained@example.com, live@example.com").deliver_now

    assert_equal ["live@example.com"], ActionMailer::Base.deliveries.sole.to
  end

  # Clubhouse 2 stored addresses as typed. update_columns would run the
  # normalizer and store this one lowercase; the string form of update_all
  # writes it as given.
  test "a mixed-case person.email is dropped by the row for its lowercase form" do
    Person.where(id: @ranger.id).update_all("email = 'John@Example.com'")
    suppress_email("john@example.com")
    address = @ranger.reload.email
    assert_equal "John@Example.com", address

    contacts_email(address).deliver_now

    assert_empty ActionMailer::Base.deliveries
    log = ActionLog.find_by!(event: "email-suppressed")
    assert_equal "John@Example.com", log.data["to_email"]
    assert_equal @ranger.id, log.target_person_id
  end

  # =========================================================================
  # Left alone
  # =========================================================================

  test "with no row for any recipient, the email is unchanged after one query" do
    message = contacts_email("live@example.com, other@example.com").message
    message.cc = "cc@example.com"
    message.bcc = "bcc@example.com"
    before = message.encoded

    assert_queries_count(1) { SuppressedRecipientsInterceptor.delivering_email(message) }

    # The encoded message never shows Bcc.
    assert_equal before, message.encoded
    assert_equal ["bcc@example.com"], message.bcc
    assert message.perform_deliveries
  end

  # The training server's held mail never leaves.
  test "a held email is not looked at" do
    suppress_email("dead@example.com")
    message = contacts_email("dead@example.com, live@example.com").message
    message.perform_deliveries = false
    before = message.encoded

    assert_no_queries { SuppressedRecipientsInterceptor.delivering_email(message) }

    assert_equal before, message.encoded
    assert_equal ["dead@example.com", "live@example.com"], message.to
    assert_not ActionLog.exists?(event: "email-suppressed")
  end

  # =========================================================================
  # Failures
  # =========================================================================

  # A password reset matters more than one bounce.
  test "a lookup that raises lets the email go unfiltered, and says so in the error log" do
    original = EmailSuppression.method(:suppressed)
    suppress_email("dead@example.com")
    EmailSuppression.define_singleton_method(:suppressed) do |*|
      raise ActiveRecord::StatementInvalid, "Table 'email_suppression' doesn't exist"
    end

    assert_difference -> { ErrorLog.where(error_type: "email-suppression-lookup-failed").count }, 1 do
      contacts_email("dead@example.com, live@example.com").deliver_now
    end

    assert_equal ["dead@example.com", "live@example.com"], ActionMailer::Base.deliveries.sole.to
    assert_equal "TrainingSessionFullMailer",
                 ErrorLog.find_by!(error_type: "email-suppression-lookup-failed").data["mailer"]
  ensure
    EmailSuppression.define_singleton_method(:suppressed, original)
  end

  test "a skip whose action log cannot be written still reaches the live recipient" do
    original = ActionLog.method(:record)
    suppress_email("dead@example.com")
    ActionLog.define_singleton_method(:record) { |*| raise ActiveRecord::StatementInvalid, "log failed" }

    assert_difference -> { ErrorLog.where(error_type: "email-suppressed-log-failed").count }, 1 do
      contacts_email("dead@example.com, live@example.com").deliver_now
    end

    assert_equal ["live@example.com"], ActionMailer::Base.deliveries.sole.to
  ensure
    ActionLog.define_singleton_method(:record, original)
  end

  private

  # A real mailer's email, so the skip can name it: the training session full
  # notice goes to every address in its list.
  def contacts_email(addresses)
    TrainingSessionFullMailer.notify(slot: @slot, signed_up: 20, notify_email: addresses)
  end
end
