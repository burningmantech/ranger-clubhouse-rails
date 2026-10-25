# frozen_string_literal: true

require "test_helper"

# ActionMailer mail through Amazon SES: the opt-in that turns it on at boot,
# the one client every email shares, and what a delivery tries again. SES is
# always a stand-in (stub_responses), and no test sleeps.
class SesMailDeliveryTest < ActiveSupport::TestCase
  include SesTestHelper

  SLOW_DOWN = Aws::SESV2::Errors::TooManyRequestsException.new(nil, "Slow down")
  SENT = { message_id: SES_MAIL_ID }.freeze

  setup do
    @person = person(:active_ranger)
    ActionMailer::Base.deliveries.clear
  end

  # --- the opt-in ---

  test "the tests never send through SES" do
    assert_equal false, Rails.configuration.x.ses_mail_live
    assert_not SesMailDelivery.live?
    assert_equal :test, ActionMailer::Base.delivery_method
  end

  # An opt-in nobody set reads as an empty set of options, which is truthy.
  test "only a real true opts in" do
    { true => true, false => false, ActiveSupport::OrderedOptions.new => false, "true" => false,
      nil => false }.each do |value, live|
      with_ses_mail_live(value) { assert_equal live, SesMailDelivery.live?, value.inspect }
    end
  end

  # --- install! ---

  test "opted in, all mail goes through one client that tries once and logs no address" do
    restoring_delivery do
      counting_clients do |built|
        with_ses_mail_live(true) { SesMailDelivery.install! }

        assert_equal 1, built.size
        assert_same built.first, ActionMailer::Base.ses_mail_settings[:sesv2_client]
      end

      assert_equal :ses_mail, ActionMailer::Base.delivery_method
      config = ActionMailer::Base.ses_mail_settings[:sesv2_client].config
      assert_equal 0, config.retry_limit
      assert_equal 1, config.max_attempts
      assert_equal 5, config.http_open_timeout
      assert_equal 20, config.http_read_timeout
      assert_equal Aws::Log::Formatter.short.pattern, config.log_formatter.pattern
    end
  end

  test "opted out, or never opted in, nothing changes and no client is built" do
    [false, ActiveSupport::OrderedOptions.new].each do |value|
      restoring_delivery do
        settings = ActionMailer::Base.ses_mail_settings

        no_new_clients do
          with_ses_mail_live(value) { SesMailDelivery.install! }
        end

        assert_equal :test, ActionMailer::Base.delivery_method, value.inspect
        assert_equal settings, ActionMailer::Base.ses_mail_settings, value.inspect
      end
    end
  end

  test "a missing region stops the boot and says what to set" do
    restoring_delivery do
      error = with_ses_config(region: nil) do
        with_ses_mail_live(true) { assert_raises(SesMailDelivery::ConfigurationError) { SesMailDelivery.install! } }
      end

      assert_includes error.message, SesMailDelivery::LIVE_VAR
      assert_includes error.message, "AWS_REGION"
      assert_equal :test, ActionMailer::Base.delivery_method
    end
  end

  # Missing keys pass the client's construction, and would fail every email
  # when it is signed. Whatever key there is never reaches the message.
  test "missing keys stop the boot, say what to set, and print no key" do
    [Aws::Credentials.new("", ""), Aws::Credentials.new("AKIDEXAMPLEONLY", "")].each do |credentials|
      restoring_delivery do
        error = with_ses_config(credentials:) do
          with_ses_mail_live(true) { assert_raises(SesMailDelivery::ConfigurationError) { SesMailDelivery.install! } }
        end

        assert_includes error.message, SesMailDelivery::LIVE_VAR
        assert_includes error.message, "AWS_ACCESS_KEY_ID"
        assert_includes error.message, "AWS_SECRET_ACCESS_KEY"
        assert_includes error.message, "ses.env"
        assert_not_includes error.message, "AKIDEXAMPLEONLY"
        assert_equal :test, ActionMailer::Base.delivery_method
      end
    end
  end

  # ActionMailer builds the delivery method inside every mail() call, also for
  # mail that is only drawn and never sent.
  test "mail drawn under :ses_mail shares the installed client and builds none of its own" do
    restoring_delivery do
      with_ses_mail_live(true) { SesMailDelivery.install! }
      client = ActionMailer::Base.ses_mail_settings[:sesv2_client]

      no_new_clients do
        messages = [
          RbsMailer.broadcast(subject: "Muster", rbs_message: "Report to HQ", alert: Alert.find(Alert::SHIFT_MUSTER),
                              expires_at: nil).message,
          PasswordResetMailer.notify(person: @person, reset_token: "token").message,
          PasskeyMailer.added(person: @person, nickname: "Laptop", by: @person).message
        ]
        html = ProspectiveApplicationStatusMail.preview(prospective_application(:pending_qualified),
                                                        ProspectiveApplication::STATUS_MORE_HANDLES, "Try again")

        assert_includes html, "Try again"
        messages.each { |message| assert_same client, message.delivery_method.settings[:sesv2_client] }
      end
    end
  end

  # --- delivery ---

  test "an email reaches SES as the mailer built it, and keeps the id SES gave it" do
    with_ses_mail do |calls|
      message = PasswordResetMailer.notify(person: @person, reset_token: "token").deliver_now

      assert_equal 1, calls.size
      assert_equal [@person.email], calls.first[:destination][:to_addresses]
      # SES reads the From off the message, display name and all.
      assert_nil calls.first[:from_email_address]
      sent = Mail.new(calls.first[:content][:raw][:data])
      assert_equal "Ranger Clubhouse <#{EmailAddresses::DO_NOT_REPLY}>", sent[:from].to_s
      assert_equal [@person.email], sent.to
      assert_equal message.subject, sent.subject
      assert_equal SES_MAIL_ID, message.header[:ses_message_id].value
    end

    assert_empty ActionMailer::Base.deliveries
  end

  # --- retries ---

  test "a throttled email is tried again and sent once" do
    on_clock(0.0) do |pauses|
      with_ses_mail(answering(SLOW_DOWN, SENT)) do |calls|
        message = send_reset

        assert_equal 2, calls.size
        assert_equal [0.5], pauses
        assert_equal SES_MAIL_ID, message.header[:ses_message_id].value
      end
    end

    assert_equal 0, ErrorLog.where(error_type: "ses-mail-exception").count
  end

  test "three throttles fail the email, with one error log that names no address" do
    on_clock(0.0) do |pauses|
      with_ses_mail(answering(SLOW_DOWN, SLOW_DOWN, SLOW_DOWN, SENT)) do |calls|
        assert_raises(Aws::SESV2::Errors::TooManyRequestsException) { send_reset }

        assert_equal 3, calls.size
        assert_equal [0.5, 1.0], pauses
      end
    end

    logs = ErrorLog.where(error_type: "ses-mail-exception").to_a
    assert_equal 1, logs.size
    assert_equal "PasswordResetMailer", logs.first.data["mailer"]
    assert_equal 3, logs.first.data["attempts"]
    logged = logs.first.data.to_json
    assert_not_includes logged, @person.email
    assert_not_includes logged, EmailAddresses::DO_NOT_REPLY
    assert_not_includes logged, "reset-token"
  end

  # SES turned each of these away, or never heard it, so it sent nothing.
  {
    "an SES limit reached" => Aws::SESV2::Errors::LimitExceededException.new(nil, "Limit"),
    "a refused connection" => Errno::ECONNREFUSED.new,
    "a refused connection the SDK wrapped" => Seahorse::Client::NetworkingError.new(Errno::ECONNREFUSED.new)
  }.each do |what, error|
    test "#{what} is tried again" do
      on_clock(0.0) do
        with_ses_mail(answering(error, SENT)) do |calls|
          message = send_reset

          assert_equal 2, calls.size
          assert_equal SES_MAIL_ID, message.header[:ses_message_id].value
        end
      end
    end
  end

  # SES may have sent each of these already, or the next try would fail the
  # same way.
  {
    "an answer that never came" => [Seahorse::Client::NetworkingError.new(Net::ReadTimeout.new),
                                    Seahorse::Client::NetworkingError],
    "a fault at SES's end" => [{ status_code: 500, headers: { "x-amzn-ErrorType" => "InternalFailure" }, body: "{}" },
                               Aws::SESV2::Errors::InternalFailure],
    "SES rejected the message" => [Aws::SESV2::Errors::MessageRejected.new(nil, "Rejected"),
                                   Aws::SESV2::Errors::MessageRejected],
    "no SES keys" => [Aws::Errors::MissingCredentialsError.new, Aws::Errors::MissingCredentialsError]
  }.each do |what, (answer, error_class)|
    test "#{what} fails the email at once" do
      on_clock(0.0) do |pauses|
        with_ses_mail(answering(answer, SENT)) do |calls|
          assert_raises(error_class) { send_reset }

          assert_equal 1, calls.size
          assert_empty pauses
        end
      end

      assert_equal 1, ErrorLog.where(error_type: "ses-mail-exception").last.data["attempts"]
    end
  end

  # A connection that timed out took 5 s: no try may start past 4 s, or a
  # delivery could outlast the 30 s a deploy waits for it.
  test "a first try that took 5 s is not tried again" do
    on_clock(0.0, 5.0) do |pauses|
      with_ses_mail(answering(SLOW_DOWN, SENT)) do |calls|
        assert_raises(Aws::SESV2::Errors::TooManyRequestsException) { send_reset }

        assert_equal 1, calls.size
        assert_empty pauses
      end
    end
  end

  test "a try starts only while its pause still fits in the time allowed" do
    on_clock(0.0, 3.2) do |pauses|
      with_ses_mail(answering(SLOW_DOWN, SLOW_DOWN, SENT)) do |calls|
        assert_raises(Aws::SESV2::Errors::TooManyRequestsException) { send_reset }

        assert_equal 2, calls.size
        assert_equal [0.5], pauses
      end
    end
  end

  test "an error log that cannot be written never hides SES's error" do
    original = ErrorLog.method(:record_exception)
    ErrorLog.define_singleton_method(:record_exception) { |*, **| raise ActiveRecord::ConnectionNotEstablished }

    with_ses_mail(answering(Aws::SESV2::Errors::MessageRejected.new(nil, "Rejected"))) do
      assert_raises(Aws::SESV2::Errors::MessageRejected) { send_reset }
    end
  ensure
    ErrorLog.define_singleton_method(:record_exception, original)
  end

  private

  def send_reset
    PasswordResetMailer.notify(person: @person, reset_token: "token").deliver_now
  end

  # A stand-in SES that gives each answer in turn: raised when it is an error.
  def answering(*answers)
    ->(_context) { (answer = answers.shift).is_a?(Exception) ? raise(answer) : answer }
  end

  # Runs the block on a clock that reads each time given in turn, then the last
  # one from there on, with every pause recorded instead of slept.
  def on_clock(*times)
    pauses = []
    clock = SesMailDelivery.method(:clock)
    pause = SesMailDelivery.method(:pause)
    SesMailDelivery.define_singleton_method(:clock) { (times.size > 1) ? times.shift : times.first }
    SesMailDelivery.define_singleton_method(:pause) { |seconds| pauses << seconds }
    yield pauses
  ensure
    SesMailDelivery.define_singleton_method(:clock, clock)
    SesMailDelivery.define_singleton_method(:pause, pause)
  end

  def with_ses_mail_live(value)
    original = Rails.configuration.x.ses_mail_live
    Rails.configuration.x.ses_mail_live = value
    yield
  ensure
    Rails.configuration.x.ses_mail_live = original
  end

  # Builds SES clients for one block as if the server's own settings were
  # these, as aws-sdk-rails hands them to every client.
  def with_ses_config(options)
    previous = Aws.config[:sesv2]
    Aws.config[:sesv2] = previous.merge(options)
    yield
  ensure
    Aws.config[:sesv2] = previous
  end

  # Builds SES clients as usual for one block, keeping each one built.
  def counting_clients
    built = []
    original = Aws::SESV2::Client.method(:new)
    Aws::SESV2::Client.define_singleton_method(:new) do |*args, **options|
      original.call(*args, **options).tap { |client| built << client }
    end
    yield built
  ensure
    Aws::SESV2::Client.define_singleton_method(:new, original)
  end

  # Any SES client built in the block raises.
  def no_new_clients
    original = Aws::SESV2::Client.method(:new)
    Aws::SESV2::Client.define_singleton_method(:new) { |*, **| raise "an SES client was built" }
    yield
  ensure
    Aws::SESV2::Client.define_singleton_method(:new, original)
  end
end
