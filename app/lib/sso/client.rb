# frozen_string_literal: true

require "net/http"
require "openssl"
require "zlib"

module Sso
  # The client side of single sign-on: the address a person is sent to, and
  # the two calls that turn the code they come back with into a person id.
  class Client
    class Error < StandardError; end

    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 10

    # Sends one request and answers with its status and body. Kept swappable
    # so a test can stand in for the other Clubhouse without a network.
    DEFAULT_TRANSPORT = lambda do |uri, request|
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                      open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) do |http|
        response = http.request(request)
        [response.code.to_i, response.body.to_s]
      end
    end

    class_attribute :transport, default: DEFAULT_TRANSPORT, instance_writer: false

    # Everything net/http raises for a peer that is down, slow, or talking
    # nonsense. Timeout::Error covers the open, read and write timeouts;
    # SystemCallError covers every Errno.
    NETWORK_ERRORS = [
      Timeout::Error, SocketError, SystemCallError, IOError, OpenSSL::SSL::SSLError,
      Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError, Zlib::Error
    ].freeze

    def initialize
      @settings = Sso.client_settings
    end

    # Where to send someone so the other Clubhouse signs them in and sends
    # them back to redirect_uri with a code and this same state. A query the
    # configured address already carries is kept, as the protocol requires.
    def authorize_url(state:, redirect_uri:)
      uri = URI.parse(@settings.authorize_url)
      query = { response_type: "code", client_id: @settings.client_id,
                redirect_uri: redirect_uri, scope: Sso::SCOPE, state: state }
      uri.query = [uri.query.presence, query.to_query].compact.join("&")
      uri.to_s
    end

    # Trade a code for the id of the person the other Clubhouse vouches for.
    #
    # @raise [Error] when the other Clubhouse cannot be reached, or answers
    #   with anything but a token and then a person
    def exchange(code, redirect_uri:)
      token = post_form(@settings.token_url,
                        grant_type: "authorization_code", code: code, redirect_uri: redirect_uri,
                        client_id: @settings.client_id,
                        client_secret: @settings.client_secret)["access_token"]
      raise Error, "the token reply carried no access token" if token.blank?

      chid = Integer(get(@settings.userinfo_url, "Authorization" => "Bearer #{token}")["chid"],
                     exception: false)
      raise Error, "userinfo named no person" unless chid&.positive?

      chid
    end

    private

    def post_form(url, fields)
      request(url) do |uri|
        Net::HTTP::Post.new(uri, "Accept" => "application/json").tap { |post| post.set_form_data(fields) }
      end
    end

    def get(url, headers)
      request(url) { |uri| Net::HTTP::Get.new(uri, headers.merge("Accept" => "application/json")) }
    end

    # The parsed reply, or an Error naming the address and what went wrong.
    # The message never carries what was sent, so it is safe to log.
    def request(url)
      uri = URI.parse(url)
      raise Error, "#{url} is not a full http(s) address" unless uri.is_a?(URI::HTTP)

      http_request = yield uri
      status, body = transport.call(uri, http_request)
      unless status == 200
        raise Error, "#{uri.host} answered #{status} to #{http_request.method} #{uri.path}"
      end

      parsed = JSON.parse(body)
      raise Error, "#{uri.host} answered with something other than a JSON object" unless parsed.is_a?(Hash)

      parsed
    rescue *NETWORK_ERRORS, JSON::ParserError, URI::InvalidURIError => e
      raise Error, "#{url}: #{e.class}: #{e.message}"
    end
  end
end
