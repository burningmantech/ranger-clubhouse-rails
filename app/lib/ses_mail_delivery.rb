# frozen_string_literal: true

#
# ActionMailer mail through Amazon SES: every email the Clubhouse sends except
# broadcast email, which Rbs hands SES itself with SendBulkEmail.
#
# This is the :ses_mail delivery method, registered by
# config/initializers/mail_delivery.rb in every environment and chosen there
# only once a server opts in (config.x.ses_mail_live, set in production from
# RANGER_CLUBHOUSE_SES_MAIL_LIVE). Until then mail goes by SMTP, or in the
# tests into ActionMailer::Base.deliveries.
#
# It is the gem's SES v2 delivery method: SendEmail with the raw message, and
# the id SES gave the email in the ses_message_id header, which
# MailLog.record_delivery keeps. It tries again only when SES certainly never
# took the email, so nobody gets one twice.
#
class SesMailDelivery < Aws::ActionMailer::SESV2::Mailer
  LIVE_VAR = "RANGER_CLUBHOUSE_SES_MAIL_LIVE"

  class ConfigurationError < StandardError; end

  # The client every delivery shares, built as Rbs builds its own.
  #
  # The SDK's own retries are off. SendEmail carries no way to say "this is the
  # same email again", so a retry after a timeout SES had in fact answered
  # would send it twice; the tries below are the only ones. No connection in
  # 5 s means nothing went; no answer in 20 s fails the email, which may have
  # gone.
  #
  # The short log line is not optional: the SDK logs to Rails.logger, and its
  # usual line would write every recipient and the start of the message --
  # a password reset's link among it -- into the production log.
  CLIENT_OPTIONS = {
    retry_limit: 0, max_attempts: 1, http_open_timeout: 5, http_read_timeout: 20,
    log_formatter: Aws::Log::Formatter.short
  }.freeze

  # SES turning the whole call away before taking anything because it was asked
  # too fast -- by a broadcast filling the account's send rate, say.
  THROTTLES = [Aws::SESV2::Errors::TooManyRequestsException, Aws::SESV2::Errors::LimitExceededException].freeze

  # The pause before each try after the first, so three tries at most. A
  # throttle SES answers at once gets all three within about 2 s.
  RETRY_PAUSES = [0.5, 1.0].freeze

  # A try starts only while the time since the first one began, its pause
  # included, is at most this. One try takes 25 s at most (CLIENT_OPTIONS), so
  # a delivery ends within 29 s: inside the 30 s a deploy waits for a running
  # job (config.solid_queue.shutdown_timeout), which therefore never cuts a call
  # off. A connection that timed out (5 s) is never tried again; one refused at
  # once is.
  RETRY_WINDOW = 4.0

  class << self
    # Whether this server sends its mail through SES. Only a real true counts:
    # a config.x key nobody set reads as an empty set of options, which is
    # truthy.
    def live?
      Rails.configuration.x.ses_mail_live == true
    end

    #
    # Sends all ActionMailer mail through SES from here on, if this server has
    # opted in; otherwise changes nothing. Called once at boot.
    #
    # Builds the one client every delivery shares. ActionMailer builds the
    # delivery method inside every mail() call, before anything is sent, so
    # without it each would build a client and look up the keys again -- also
    # for mail that never goes out, such as a preview or the training server's.
    #
    # A missing region or missing keys stop the boot, so a server set up wrong
    # shows it when it is started rather than in a member's password reset.
    # Nothing here asks AWS anything, so no connection is open when Puma forks.
    #
    def install!
      return unless live?

      ActionMailer::Base.ses_mail_settings = { sesv2_client: shared_client }
      ActionMailer::Base.delivery_method = :ses_mail
    end

    # Seconds by a clock that only moves forward. Its own method so a test can
    # say how long a try took.
    def clock
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    # Waits before trying again. Its own method so a test never sleeps.
    def pause(seconds)
      sleep(seconds)
    end

    private

    def shared_client
      client = begin
        Aws::SESV2::Client.new(**CLIENT_OPTIONS)
      rescue Aws::Errors::MissingRegionError
        raise ConfigurationError, "#{LIVE_VAR} sends mail through Amazon SES, but no region is set. " \
                                  "Set AWS_REGION to the region SES sends from."
      end
      return client if client.config.credentials&.set?

      raise ConfigurationError, "#{LIVE_VAR} sends mail through Amazon SES, but its keys are missing. " \
                                "Set AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY in ses.env."
    end
  end

  #
  # Sends one email, trying again only when SES certainly never took it: it
  # was asked too fast, or no connection was ever made. Anything else -- a
  # read timeout or a fault at SES's end, which may have sent it already, or a
  # refusal the next try would meet too -- fails the email at once. When it
  # gives up, the error is written to the error log and raised.
  #
  def deliver!(message)
    started = self.class.clock
    attempts = 0
    begin
      attempts += 1
      super
    rescue => e
      wait = RETRY_PAUSES[attempts - 1]
      if wait && never_sent?(e) && self.class.clock - started + wait <= RETRY_WINDOW
        self.class.pause(wait)
        retry
      end

      record_failure(e, message, attempts)
      raise
    end
  end

  private

  # A throttle, or a connection never made, whether raised bare or inside the
  # SDK's networking error -- read as Rbs.call_failure_status reads it.
  def never_sent?(error)
    error = error.original_error if error.is_a?(Seahorse::Client::NetworkingError)
    [*THROTTLES, *Rbs::NEVER_CONNECTED].any? { |refusal| error.is_a?(refusal) }
  end

  # Without this a failure in a request -- a password reset, say -- shows only
  # in the server log. It names the mailer, never an address or the body. A
  # log that cannot be written never hides SES's error.
  def record_failure(error, message, attempts)
    ErrorLog.record_exception(error, "ses-mail-exception",
                              extra: { mailer: message.delivery_handler&.name, attempts: })
  rescue StandardError
    nil
  end
end
