# frozen_string_literal: true

# twilio-ruby loads Faraday only once a real client makes a call;
# slow_answer? names its timeout before then.
require "faraday"

# What Administration › SMS Management needs before it can ask Twilio
# anything: the settings the Clubhouse texts with, a client for them, and how
# to say what went wrong. TwilioStatus answers for the account panel, and
# TwilioMessageLog for the log.
module SmsManagement
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

  # A bare IPv4 address in any spelling Twilio would resolve: 127.0.0.1, but
  # also 127.1, 2130706433, 0x7f000001 and 010.0.0.1.
  NUMERIC_HOST = /\A(?:0x\h*|\d+)(?:\.(?:0x\h*|\d+))*\z/i

  module_function

  # The settings the Clubhouse texts with, read as SmsService.broadcast reads
  # them: the service ids split on commas and nothing more, so a stray space
  # shows up here as an id Twilio cannot be asked about (UNUSABLE_ID) rather
  # than being tidied away while broadcasts fail on it.
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

  # Whether this server may change where Twilio sends incoming texts. Every
  # copy of the database holds the live credentials, so only the server Twilio
  # should post to is set up for it (RANGER_CLUBHOUSE_TWILIO_INCOMING_LIVE),
  # and never the training server.
  def incoming_changes_allowed?
    Rails.configuration.x.twilio_incoming_live == true && !Current.is_ghd_server?
  end

  # Why Twilio cannot post incoming texts to url, or nil when it can: it posts
  # them from the internet, so the address must be https on a public name. A
  # query is refused as well: the action log keeps the address as typed.
  def incoming_url_problem(url)
    uri = URI.parse(url.to_s)
    return "the address must start with https://" unless uri.is_a?(URI::HTTPS) && uri.host.present?
    return "the address must not carry a user name or password" if uri.userinfo
    return "the address must stop at its path, with no ? or # part" if uri.query || uri.fragment
    return "#{uri.host} is not a public name Twilio can reach" if local_host?(uri.host)

    nil
  rescue URI::InvalidURIError
    "that is not a web address"
  end

  # A bare IP address, or a name only a local network knows: one with no dot,
  # or under a suffix kept for local use. Case and a trailing dot do not count.
  def local_host?(host)
    name = host.downcase.delete_suffix(".")
    name.include?(":") || NUMERIC_HOST.match?(name) || !name.include?(".") ||
      name.end_with?(".localhost", ".test", ".local", ".internal")
  end

  # Points every Messaging Service behind the Notify services at url, so
  # Twilio posts each incoming text there, starting with the next one. Each
  # also drops its fallback address and stops deferring to its numbers' own
  # webhooks, or a text could still go somewhere else.
  #
  # { changed: [{ service:, before: }] }, each before being how the service
  # handled incoming texts until now. With error: too when Twilio stopped
  # partway, and unsure: the service whose change went out with no answer
  # back, which Twilio may have made. nil while the settings to ask with are
  # missing.
  def point_incoming_texts(url)
    unless incoming_changes_allowed?
      return { changed: [], error: "this server is not set up to change where Twilio sends incoming texts" }
    end

    client = self.client or return
    changed = []
    pending = nil
    service_ids = settings[:service_ids]
    unless service_ids.all? { |id| usable_id?(id) }
      return { changed:, error: "TwilioServiceId holds an id that is empty or has a space or punctuation in it" }
    end

    messaging_sids = service_ids.filter_map { |id| client.notify.v1.services(id).fetch.messaging_service_sid.presence }
    return { changed:, error: "no Notify service sends through a Messaging Service" } if messaging_sids.empty?

    messaging_sids.uniq.each do |sid|
      service = client.messaging.v1.services(sid)
      pending = { service: sid, before: incoming_setup(service.fetch) }
      service.update(inbound_request_url: url, inbound_method: "POST", fallback_url: "",
                     use_inbound_webhook_on_number: false)
      changed << pending
      pending = nil
    end
    { changed: }
  rescue *ERRORS => e
    { changed:, unsure: (pending if unanswered?(e)), error: describe(e) }.compact
  end

  # How a Messaging Service handles incoming texts: everything the update
  # changes, so a change can be put back.
  def incoming_setup(service)
    { url: service.inbound_request_url, method: service.inbound_method, fallback_url: service.fallback_url.presence,
      defers_to_number: service.use_inbound_webhook_on_number == true }
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
