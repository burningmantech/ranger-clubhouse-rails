# frozen_string_literal: true

# Which side of single sign-on this Clubhouse is on, read from the environment.
#
# Nothing is set on the machines that keep their own sign-in form: every
# development machine and, until the switch is thrown, production. A server
# signs people in for other websites (the learning site, the HQ ticket desk).
# A client sends people to another Clubhouse to sign in and takes its word for
# who came back. The two are never on at once.
module Sso
  MODE_VAR = "RANGER_CLUBHOUSE_SSO_MODE"
  SERVER = "server"
  CLIENT = "client"
  MODES = [SERVER, CLIENT].freeze

  # What a client needs to know about the Clubhouse it signs in through. The
  # three addresses are spelled out rather than discovered: Clubhouse 2 does
  # not publish its discovery document, and its paths are not this app's.
  CLIENT_VARS = {
    client_id: "RANGER_CLUBHOUSE_SSO_CLIENT_ID",
    client_secret: "RANGER_CLUBHOUSE_SSO_CLIENT_SECRET",
    authorize_url: "RANGER_CLUBHOUSE_SSO_AUTHORIZE_URL",
    token_url: "RANGER_CLUBHOUSE_SSO_TOKEN_URL",
    userinfo_url: "RANGER_CLUBHOUSE_SSO_USERINFO_URL"
  }.freeze
  CLIENT_URL_VARS = %i[authorize_url token_url userinfo_url].freeze

  # What a client asks for and what the server offers. Nothing narrower: the
  # websites are all trusted, and userinfo says the same whatever was asked.
  SCOPES = %w[openid email profile].freeze
  SCOPE = SCOPES.join(" ")

  ClientSettings = Data.define(*CLIENT_VARS.keys)

  class ConfigurationError < StandardError; end

  class << self
    def mode
      #ENV[MODE_VAR].presence
      "server"
    end

    def server?
      mode == SERVER
    end

    def client?
      mode == CLIENT
    end

    # The five client values, read afresh each time so a test can change them
    # without a restart.
    def client_settings
      ClientSettings.new(**CLIENT_VARS.transform_values { |var| ENV[var].to_s.strip })
    end

    # The website a client sends people to, for the sign-in page to name.
    def server_host
      URI.parse(client_settings.authorize_url).host
    rescue URI::InvalidURIError
      nil
    end

    # A full web address, the only kind a person can be sent to or a request
    # made to.
    def http_url?(value)
      URI.parse(value).is_a?(URI::HTTP)
    rescue URI::InvalidURIError
      false
    end

    # Refuse to boot with a mode that means nothing, or as a client missing
    # what it needs to sign anyone in. Better than the first person to try.
    def validate!
      return if mode.nil?

      unless MODES.include?(mode)
        raise ConfigurationError, "#{MODE_VAR} must be #{MODES.join(" or ")}, not #{mode.inspect}"
      end
      return unless client?

      missing = CLIENT_VARS.values.select { |var| ENV[var].blank? }
      raise ConfigurationError, "Client mode needs #{missing.join(", ")}" if missing.any?

      settings = client_settings
      CLIENT_URL_VARS.each do |name|
        next if http_url?(settings.public_send(name))

        raise ConfigurationError, "#{CLIENT_VARS.fetch(name)} must be a full http(s) address"
      end
    end
  end
end
