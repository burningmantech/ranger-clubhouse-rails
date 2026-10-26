# frozen_string_literal: true

# twilio-ruby loads Faraday only once a real client makes a call;
# slow_answer? names its timeout before then.
require "faraday"

# The Twilio account the Clubhouse texts through: its settings, the one place
# a client for it is made, and how to say what went wrong when it is asked
# something. SmsService sends with it; Administration › SMS Management reads
# with it (TwilioStatus for the account panel, TwilioMessageLog for the log)
# and changes where incoming texts go (SmsManagement).
module TwilioAccount
  # Seconds to connect, and again to read, for each call to Twilio.
  TIMEOUT = 5

  # What a call to Twilio can raise: Twilio's own refusal (a RestError), no
  # answer at all (any other TwilioError), an answer that is not JSON, or an
  # id that cannot go in an address, which is never sent.
  ERRORS = [Twilio::REST::TwilioError, JSON::ParserError, URI::InvalidURIError].freeze

  # Twilio ids are letters and digits. Anything else -- an empty entry, the
  # space after a comma -- cannot be asked about.
  TWILIO_ID = /\A[A-Za-z0-9]+\z/
  UNUSABLE_ID = "the id is empty or holds a space or punctuation, so Twilio cannot be asked about it, " \
                "and broadcasts through it fail too"

  module_function

  # The settings the Clubhouse texts with, broadcasts included: the service
  # ids split on commas and nothing more, so a stray space shows up as an id
  # Twilio cannot be asked about (UNUSABLE_ID) rather than being tidied away
  # while broadcasts fail on it.
  def settings
    values = Setting.get_value([Setting::TWILIO_ACCOUNT_SID, Setting::TWILIO_AUTH_TOKEN,
                                Setting::TWILIO_SERVICE_ID, Setting::BROADCAST_SMS_SANDBOX])

    { account_sid: values[Setting::TWILIO_ACCOUNT_SID].presence,
      auth_token: values[Setting::TWILIO_AUTH_TOKEN].presence,
      service_ids: values[Setting::TWILIO_SERVICE_ID].to_s.split(","),
      sandbox: values[Setting::BROADCAST_SMS_SANDBOX] }
  end

  def usable_id?(id) = TWILIO_ID.match?(id)

  # A client for the configured account, or nil while the settings to ask
  # with are missing.
  def client
    sid, token = settings.values_at(:account_sid, :auth_token)
    build_client(sid, token) if sid && token
  end

  # The one place a client is made, so a test can hand in its own.
  def build_client(sid, token)
    Twilio::REST::Client.new(sid, token, nil, nil, Twilio::HTTP::Client.new(timeout: TIMEOUT))
  end

  # Whether the call went out and no answer came back, so it may have been
  # carried out. A RestError is Twilio's answer, and a bad id is never sent.
  def unanswered?(error)
    !error.is_a?(Twilio::REST::RestError) && !error.is_a?(URI::InvalidURIError)
  end

  # Whether the call reached Twilio but its answer was too slow: a read
  # timeout, which twilio-ruby raises with Faraday's as its cause. Twilio may
  # answer the next call; a connection that failed would fail it too.
  def slow_answer?(error) = error.cause.is_a?(Faraday::TimeoutError)

  # What Twilio said, or why it could not be asked, in a line.
  def describe(error)
    case error
    when Twilio::REST::RestError
      "#{error.error_message.presence || 'Twilio refused the request'} (Twilio error #{error.code})"
    when URI::InvalidURIError
      "a Twilio setting holds a space or punctuation, so Twilio cannot be asked"
    when JSON::ParserError
      "Twilio's answer could not be read"
    else
      "Could not reach Twilio: #{error.message}"
    end
  end
end
