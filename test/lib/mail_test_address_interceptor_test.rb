# frozen_string_literal: true

require "test_helper"

# One test inbox for all mail, set by RANGER_CLUBHOUSE_MAIL_TEST_ADDRESS.
class MailTestAddressInterceptorTest < ActiveSupport::TestCase
  include EnvTestHelper
  include SesTestHelper

  VAR = MailTestAddressInterceptor::ADDRESS_VAR
  INBOX = "inbox@example.com"

  setup do
    ActionMailer::Base.deliveries.clear
  end

  teardown do
    Current.reset
  end

  test "it is registered for every email" do
    assert_includes Mail.delivery_interceptors, MailTestAddressInterceptor
  end

  test "unset, an email is left as it is" do
    [nil, "", "  "].each do |value|
      message = email
      before = message.encoded

      with_env(VAR => value) { MailTestAddressInterceptor.delivering_email(message) }

      # The encoded message never shows Bcc.
      assert_equal before, message.encoded, value.inspect
      assert_equal ["delta@example.com"], message.bcc, value.inspect
    end
  end

  test "set, an email goes only to the test inbox and names who it was for" do
    message = email
    body = message.body.decoded

    with_env(VAR => " #{INBOX} ") { MailTestAddressInterceptor.delivering_email(message) }

    assert_equal [INBOX], message.to
    assert_nil message.cc
    assert_nil message.bcc
    assert_nil message.header[:cc]
    assert_nil message.header[:bcc]
    assert_equal "able@example.com, baker@example.com, charlie@example.com, delta@example.com",
                 message.header[MailTestAddressInterceptor::RECIPIENTS_HEADER].value
    assert_equal "Your shift tomorrow", message.subject
    assert_equal body, message.body.decoded
  end

  # SMTP, and SES, would send to the envelope instead of To.
  test "set, an envelope recipient set by hand is cleared too" do
    message = email
    message.smtp_envelope_to = "envelope@example.com"

    with_env(VAR => INBOX) { MailTestAddressInterceptor.delivering_email(message) }

    assert_equal [INBOX], message.smtp_envelope_to
  end

  # The training server's held mail keeps its real recipients.
  test "a held email is left as it is" do
    message = email
    message.perform_deliveries = false
    before = message.encoded

    with_env(VAR => INBOX) { MailTestAddressInterceptor.delivering_email(message) }

    assert_equal before, message.encoded
    assert_equal ["delta@example.com"], message.bcc
  end

  # The mail log names the test inbox too, so SES's reports for it stamp the
  # row it wrote.
  test "an email sent and logged goes to the test inbox, and its mail log row says so" do
    Current.person = person(:auditor_ranger)
    application = prospective_application(:pending_qualified)

    with_env(VAR => INBOX) do
      with_ses_mail do |calls|
        assert_difference "MailLog.count", 1 do
          ProspectiveApplicationStatusMail.execute(application, ProspectiveApplication::STATUS_HOLD_AGE_ISSUE)
        end

        assert_equal 1, calls.size
        assert_equal [INBOX], calls.first[:destination][:to_addresses]
        assert_nil calls.first[:destination][:cc_addresses]
        assert_nil calls.first[:destination][:bcc_addresses]
        sent = Mail.new(calls.first[:content][:raw][:data])
        assert_equal application.email, sent.header[MailTestAddressInterceptor::RECIPIENTS_HEADER].value
      end
    end

    log = MailLog.order(:id).last
    assert_equal INBOX, log.to_email
    assert_equal SES_MAIL_ID, log.message_id
    assert_equal application.id, log.prospective_application_id
  end

  test "unset, or one address SES would take, boots" do
    [nil, "", INBOX, " #{INBOX} "].each do |value|
      with_env(VAR => value) { assert_nothing_raised { MailTestAddressInterceptor.validate! } }
    end
  end

  test "a test address that is not one usable address stops the boot and names the variable" do
    ["not an address", "able@example.com, baker@example.com", "Able <able@example.com>", "...@example.com",
     "able@example"].each do |value|
      with_env(VAR => value) do
        error = assert_raises(MailTestAddressInterceptor::ConfigurationError, value.inspect) do
          MailTestAddressInterceptor.validate!
        end
        assert_includes error.message, VAR
      end
    end
  end

  private

  def email
    Mail.new(from: "do-not-reply@burningman.org", to: ["Able <able@example.com>", "baker@example.com"],
             cc: "charlie@example.com", bcc: "delta@example.com", subject: "Your shift tomorrow",
             body: "See you there.")
  end
end
