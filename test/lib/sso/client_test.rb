# frozen_string_literal: true

require "test_helper"

# The client side of single sign-on against a stand-in for the other
# Clubhouse: what goes out, what comes back, and what counts as a failure.
class Sso::ClientTest < ActiveSupport::TestCase
  include SsoTestHelper

  RETURN_TO = "https://here.example.org/sso/callback"
  TOKEN_REPLY = [200, { access_token: "tok", token_type: "Bearer" }.to_json].freeze

  setup do
    set_sso_mode(Sso::CLIENT)
  end

  test "the sign-in address carries the client id, the return address, the scope and the state" do
    uri = URI.parse(Sso::Client.new.authorize_url(state: "abc123", redirect_uri: RETURN_TO))

    assert_equal "clubhouse.example.org", uri.host
    assert_equal "/sso/authorize", uri.path
    query = Rack::Utils.parse_query(uri.query)
    assert_equal "code", query["response_type"]
    assert_equal "clubhouse3", query["client_id"]
    assert_equal RETURN_TO, query["redirect_uri"]
    assert_equal "openid email profile", query["scope"]
    assert_equal "abc123", query["state"]
  end

  test "a sign-in address that already has a query keeps it" do
    set_sso_mode(Sso::CLIENT, authorize_url: "https://clubhouse.example.org/grant?tenant=rangers")

    url = Sso::Client.new.authorize_url(state: "s", redirect_uri: RETURN_TO)
    query = Rack::Utils.parse_query(URI.parse(url).query)

    assert_equal "rangers", query["tenant"]
    assert_equal "s", query["state"]
  end

  test "a code is traded for the person the other Clubhouse names" do
    stub_sso_transport(token: TOKEN_REPLY, userinfo: [200, { chid: 1234, username: "firecracker" }.to_json])

    assert_equal 1234, Sso::Client.new.exchange("the-code", redirect_uri: RETURN_TO)

    token_call, userinfo_call = sso_calls
    assert_equal "POST", token_call[:request].method
    assert_equal "/sso/token", token_call[:uri].path
    assert_equal({ "grant_type" => "authorization_code", "code" => "the-code", "redirect_uri" => RETURN_TO,
                   "client_id" => "clubhouse3",
                   "client_secret" => DEFAULT_CLIENT_SETTINGS[:client_secret] },
                 Rack::Utils.parse_query(token_call[:request].body))
    assert_equal "GET", userinfo_call[:request].method
    assert_equal "/sso/userinfo", userinfo_call[:uri].path
    assert_equal "Bearer tok", userinfo_call[:request]["Authorization"]
  end

  test "a person id sent as text still counts" do
    stub_sso_transport(token: TOKEN_REPLY, userinfo: [200, { chid: "42" }.to_json])

    assert_equal 42, Sso::Client.new.exchange("c", redirect_uri: RETURN_TO)
  end

  {
    "a token reply that is not 200" => [[401, { error: "invalid_client" }.to_json], nil, /answered 401/],
    "a token reply with no token" => [[200, { token_type: "Bearer" }.to_json], nil, /no access token/],
    "a token reply that is not JSON" => [[200, "<html>"], nil, /ParserError/],
    "a userinfo reply with no person" => [TOKEN_REPLY, [200, { email: "x@y.z" }.to_json], /named no person/],
    "a userinfo reply that is not an object" => [TOKEN_REPLY, [200, "[]"], /other than a JSON object/]
  }.each do |description, (token, userinfo, message)|
    test "#{description} is a failure" do
      stub_sso_transport(token: token, userinfo: userinfo)

      error = assert_raises(Sso::Client::Error) { Sso::Client.new.exchange("c", redirect_uri: RETURN_TO) }
      assert_match message, error.message
    end
  end

  # Each of these is what net/http raises for a peer that is up but broken,
  # and none of them is a subclass of the errors a refused connection raises.
  [Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError, Net::WriteTimeout, Zlib::DataError,
   Net::OpenTimeout, EOFError, OpenSSL::SSL::SSLError].each do |klass|
    test "a peer that raises #{klass} is a failure, not a crash" do
      Sso::Client.transport = ->(_uri, _request) { raise klass, "peer" }

      error = assert_raises(Sso::Client::Error) { Sso::Client.new.exchange("c", redirect_uri: RETURN_TO) }
      assert_includes error.message, klass.name
    end
  end

  test "a Clubhouse that cannot be reached is a failure, and the message carries no secret" do
    stub_sso_unreachable

    error = assert_raises(Sso::Client::Error) { Sso::Client.new.exchange("c", redirect_uri: RETURN_TO) }
    assert_match(/ECONNREFUSED/, error.message)
    assert_not_includes error.message, DEFAULT_CLIENT_SETTINGS[:client_secret]
  end

  test "an address that is not a full web address is a failure, not a crash" do
    set_sso_mode(Sso::CLIENT, token_url: "clubhouse.example.org/sso/token")
    error = assert_raises(Sso::Client::Error) { Sso::Client.new.exchange("c", redirect_uri: RETURN_TO) }
    assert_match(/not a full http/, error.message)

    set_sso_mode(Sso::CLIENT, token_url: "https://clubhouse.example.org/sso token")
    error = assert_raises(Sso::Client::Error) { Sso::Client.new.exchange("c", redirect_uri: RETURN_TO) }
    assert_match(/InvalidURIError/, error.message)
  end
end
