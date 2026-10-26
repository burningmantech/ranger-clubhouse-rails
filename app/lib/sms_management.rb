# frozen_string_literal: true

# The one change Administration › SMS Management makes on Twilio: where it
# sends incoming texts, whether this server may make it, and whether an
# address will do. TwilioAccount holds the settings, the client and how to
# say what went wrong; TwilioStatus answers for the account panel, and
# TwilioMessageLog for the log.
module SmsManagement
  # A bare IPv4 address in any spelling Twilio would resolve: 127.0.0.1, but
  # also 127.1, 2130706433, 0x7f000001 and 010.0.0.1.
  NUMERIC_HOST = /\A(?:0x\h*|\d+)(?:\.(?:0x\h*|\d+))*\z/i

  module_function

  # Whether this server may change where Twilio sends incoming texts: any but
  # the training server, which holds the same live credentials.
  def incoming_changes_allowed? = !Current.is_ghd_server?

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
      return { changed: [], error: "the training server cannot change where Twilio sends incoming texts" }
    end

    client = TwilioAccount.client or return
    changed = []
    pending = nil
    service_ids = TwilioAccount.settings[:service_ids]
    unless service_ids.all? { |id| TwilioAccount.usable_id?(id) }
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
  rescue *TwilioAccount::ERRORS => e
    { changed:, unsure: (pending if TwilioAccount.unanswered?(e)), error: TwilioAccount.describe(e) }.compact
  end

  # How a Messaging Service handles incoming texts: everything the update
  # changes, so a change can be put back.
  def incoming_setup(service)
    { url: service.inbound_request_url, method: service.inbound_method, fallback_url: service.fallback_url.presence,
      defers_to_number: service.use_inbound_webhook_on_number == true }
  end
end
