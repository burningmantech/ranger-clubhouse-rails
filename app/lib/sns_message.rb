# frozen_string_literal: true

require "net/http"

# One message posted by AWS Simple Notification Service.
#
# The signature is what makes an open endpoint safe to leave open. Every SNS
# message is signed with a certificate SNS publishes, so a forged post -- which
# could otherwise mark any address in the database as bouncing, or confirm a
# subscription nobody asked for -- fails to verify and is thrown away.
#
# See https://docs.aws.amazon.com/sns/latest/dg/sns-verify-signature-of-message.html
class SnsMessage
  # The only hosts allowed to serve a signing certificate or a subscription
  # confirmation. Both URLs arrive inside the message and both are fetched, so
  # without this the sender chooses where this server makes requests.
  AWS_HOST = /\A(?:[a-z0-9-]+\.)*amazonaws\.com\z/

  # The fields the signature covers, in the order SNS joins them. A field that
  # is absent from the message is left out of the string as well -- Subject is
  # optional, and including an empty one fails every check.
  SIGNED_KEYS = {
    "Notification" => %w[Message MessageId Subject Timestamp TopicArn Type],
    "SubscriptionConfirmation" => %w[Message MessageId SubscribeURL Timestamp Token TopicArn Type],
    "UnsubscribeConfirmation" => %w[Message MessageId SubscribeURL Timestamp Token TopicArn Type]
  }.freeze

  DIGESTS = { "1" => OpenSSL::Digest::SHA1, "2" => OpenSSL::Digest::SHA256 }.freeze

  # Certificates rotate rarely and a busy topic delivers thousands of messages
  # an hour. Without this every one of them would cost an extra HTTPS round
  # trip before the app did any work.
  CERT_CACHE = 1.day

  attr_reader :envelope

  # Parse a posted body, or nil when it is not a JSON object.
  def self.parse(body)
    parsed = JSON.parse(body.to_s)
    parsed.is_a?(Hash) ? new(parsed) : nil
  rescue JSON::ParserError
    nil
  end

  def initialize(envelope)
    @envelope = envelope
  end

  def type = envelope["Type"]
  def topic_arn = envelope["TopicArn"]
  def subscribe_url = envelope["SubscribeURL"]
  def subscription_confirmation? = type == "SubscriptionConfirmation"

  # The SES event carried by the message. Normally it is JSON inside the
  # envelope's Message field; a topic set to raw delivery, or SES publishing
  # straight to this endpoint, sends the event as the whole body instead.
  def payload
    @payload ||= begin
      inner = JSON.parse(envelope["Message"].to_s)
      inner.is_a?(Hash) ? inner : envelope
    rescue JSON::ParserError, TypeError
      envelope
    end
  end

  # Older SES topic notifications say notificationType; configuration-set event
  # publishing says eventType. Both carry the same event names.
  def event_type = payload["notificationType"] || payload["eventType"]

  def message_id = payload.dig("mail", "messageId").to_s

  # The address the Clubhouse sent to, for a recipient a bounce or complaint
  # reports. SES fills the reported emailAddress from the bounce's
  # Final-Recipient, which a forwarder can change, so the one entry in
  # mail.destination wins: each broadcast email is its own SES message, and its
  # entry may carry the Ranger's name (Rbs.to_line). With no destination,
  # several, or one that does not parse, the reported address is all there is.
  def sent_address(reported)
    destination = Array(payload.dig("mail", "destination"))
    return reported unless destination.one?

    Mail::Address.new(destination.first.to_s).address.presence || reported
  rescue Mail::Field::ParseError
    reported
  end

  # Whether the message really came from SNS. Anything unexpected -- a missing
  # signature, an unknown message type, a certificate served from somewhere
  # other than AWS, a network failure fetching it -- counts as unverified.
  def verified?
    keys = SIGNED_KEYS[type]
    digest = DIGESTS[envelope["SignatureVersion"].to_s]
    signature = envelope["Signature"]
    return false if keys.nil? || digest.nil? || signature.blank?

    certificate&.public_key&.verify(digest.new, signature.unpack1("m"), canonical_string(keys)) || false
  rescue OpenSSL::OpenSSLError
    false
  end

  # Fetch a URL that arrived inside the message, but only when AWS serves it.
  # Returns the body, or nil if the host is not AWS or the request failed.
  def self.fetch_aws(url)
    uri = URI.parse(url.to_s)
    return nil unless uri.is_a?(URI::HTTPS) && uri.host.to_s.match?(AWS_HOST)

    response = Net::HTTP.get_response(uri)
    response.is_a?(Net::HTTPSuccess) ? response.body : nil
  # A URL that will not parse, or a request that never lands, leaves the
  # caller with nothing -- which is the same answer as a refusal.
  rescue URI::InvalidURIError, IOError, SystemCallError, Timeout::Error, SocketError, OpenSSL::SSL::SSLError
    nil
  end

  private

  def canonical_string(keys)
    keys.filter_map { |key| "#{key}\n#{envelope[key]}\n" if envelope.key?(key) }.join
  end

  def certificate
    pem = Rails.cache.fetch("sns/cert/#{envelope["SigningCertURL"]}", expires_in: CERT_CACHE, skip_nil: true) do
      self.class.fetch_aws(envelope["SigningCertURL"])
    end

    pem && OpenSSL::X509::Certificate.new(pem)
  end
end
