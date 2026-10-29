# frozen_string_literal: true

# Puts a test on one side of single sign-on. The mode and the client settings
# are read from the environment on every call, and nothing else in the test
# process sets them, so a test sets what it needs and the teardown here clears
# it -- along with the client's transport, which is process-wide state.
module SsoTestHelper
  extend ActiveSupport::Concern

  DEFAULT_CLIENT_SETTINGS = {
    client_id: "clubhouse3",
    client_secret: "TestClientSecretCCCCCCCCCCCCCCCC",
    authorize_url: "https://clubhouse.example.org/sso/authorize",
    token_url: "https://clubhouse.example.org/sso/token",
    userinfo_url: "https://clubhouse.example.org/sso/userinfo"
  }.freeze

  ENV_KEYS = [Sso::MODE_VAR, *Sso::CLIENT_VARS.values].freeze

  # The plain secrets behind the oauth_client fixtures, by client_id. The rows
  # hold only their digests, so this is the one place a test can read them.
  FIXTURE_SECRETS = {
    "ranger-moodle" => "TestMoodleSecretAAAAAAAAAAAAAAAA",
    "ranger-hq-osticket" => "TestOSTicketSecretBBBBBBBBBBBBBB"
  }.freeze

  def fixture_secret(client)
    FIXTURE_SECRETS.fetch(client.client_id)
  end

  included do
    teardown do
      clear_sso_env
      Sso::Client.transport = Sso::Client::DEFAULT_TRANSPORT
    end
  end

  # nil, Sso::SERVER or Sso::CLIENT. A client gets the settings above unless a
  # keyword names another value (client_id:, authorize_url:, ...).
  def set_sso_mode(mode, **overrides)
    clear_sso_env
    ENV[Sso::MODE_VAR] = mode if mode
    settings = mode == Sso::CLIENT ? DEFAULT_CLIENT_SETTINGS.merge(overrides) : overrides
    settings.each { |name, value| ENV[Sso::CLIENT_VARS.fetch(name)] = value }
  end

  # The mode for one block, then whatever the test had before it.
  def with_sso_mode(mode, **overrides)
    saved = ENV_KEYS.to_h { |key| [key, ENV.fetch(key, nil)] }
    set_sso_mode(mode, **overrides)
    yield
  ensure
    saved.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  def clear_sso_env
    ENV_KEYS.each { |key| ENV.delete(key) }
  end

  # A stand-in for the other Clubhouse: what its token endpoint and its
  # userinfo endpoint answer, each as [status, body]. Every call is kept in
  # sso_calls, in order.
  def stub_sso_transport(token:, userinfo:)
    calls = sso_calls
    Sso::Client.transport = lambda do |uri, request|
      calls << { uri: uri, request: request }
      uri.path.end_with?("/token") ? token : userinfo
    end
  end

  # The other Clubhouse when nothing is listening.
  def stub_sso_unreachable
    Sso::Client.transport = ->(_uri, _request) { raise Errno::ECONNREFUSED }
  end

  def sso_calls
    @sso_calls ||= []
  end
end
