# frozen_string_literal: true

require "ipaddr"

# Signing in with a passkey, and the one thing a deployment has to say about
# it: the address this Clubhouse answers at.
#
# A passkey belongs to the website it was made on. The browser writes that
# website's address into everything the passkey presents, and the Clubhouse
# checks it against the address it expects. It cannot take the request's word
# for that address -- production names no allowed hosts, so the Host header is
# whatever the client sent -- which is why the address is set here rather than
# read off the request. Nothing set in production means passkeys are off: no
# button, no pages, and the routes answer 404.
module Passkeys
  ORIGIN_VAR = "RANGER_CLUBHOUSE_PASSKEY_ORIGIN"

  # The name a browser shows when it asks where to save a passkey.
  RELYING_PARTY_NAME = "Ranger Clubhouse"

  class ConfigurationError < StandardError; end

  class << self
    # The address passkeys belong to, read afresh each time so a test can
    # change it without a restart. A development machine sets nothing and
    # answers at whatever port it was started on, so there the request's own
    # address stands in.
    def origin(request)
      configured_origin || local_origin(request)
    end

    # Passkeys are offered wherever the password form is, and nowhere else: a
    # single sign-on client signs no one in itself.
    def enabled?(request)
      origin(request).present? && !Sso.client?
    end

    # What the WebAuthn library checks a passkey against. Built per request
    # rather than configured once: one process answers at more than one address
    # in development, and a test sets its own.
    def relying_party(request)
      address = origin(request)
      raise ConfigurationError, "Passkeys are off here: #{ORIGIN_VAR} is not set" if address.nil?

      WebAuthn::RelyingParty.new(
        allowed_origins: [address],
        id: URI.parse(address).host,
        name: RELYING_PARTY_NAME
      )
    end

    # Refuse to boot with an address no passkey could belong to. Better than
    # every sign-in failing with nothing on the page to say why.
    def validate!
      address = configured_origin
      return if address.nil? || usable_origin?(address)

      raise ConfigurationError,
            "#{ORIGIN_VAR} must be an https address with a host name and nothing after it, " \
            "such as https://clubhouse.example.org, not #{address.inspect}"
    end

    private

    def configured_origin
      ENV[ORIGIN_VAR].to_s.strip.presence
    end

    # Scheme, host name and port, exactly as a browser reports them: lower
    # case, no default port, and not one character more. The two are compared
    # as text, so a trailing slash or a capital would fail every sign-in. An IP
    # address is refused because a browser will not make a passkey for one, and
    # plain http because it will only do so on localhost.
    def usable_origin?(address)
      uri = URI.parse(address)
      return false unless uri.is_a?(URI::HTTP) && uri.host.present?
      return false if ip_address?(uri.host)
      return false unless uri.scheme == "https" || uri.host == "localhost"

      address == uri.origin.downcase
    rescue URI::InvalidURIError
      false
    end

    # 127.0.0.1 reaches a development server as well as localhost does, but no
    # browser will make a passkey there. Offering nothing beats offering a
    # button that can only fail.
    def local_origin(request)
      return unless Rails.env.local?
      return if ip_address?(request.host)

      request.base_url
    end

    def ip_address?(host)
      IPAddr.new(host.delete("[]"))
      true
    rescue IPAddr::InvalidAddressError
      false
    end
  end
end
