# frozen_string_literal: true

require "test_helper"

# The calls a website makes to a Clubhouse in server mode: the discovery
# document, the token trade, and userinfo. Nothing here has a signed-in person.
class Sso::ApiControllerTest < ActionDispatch::IntegrationTest
  include SsoTestHelper

  setup do
    set_sso_mode(Sso::SERVER)
    OauthCode.delete_all
    ErrorLog.delete_all
    @client = oauth_client(:moodle)
    @person = person(:active_ranger)
    @code = OauthCode.issue(@client, @person, Sso::SCOPE)
  end

  def token_params(**overrides)
    { grant_type: "authorization_code", code: @code.code, client_id: @client.client_id,
      client_secret: fixture_secret(@client), redirect_uri: @client.redirect_uri }.merge(overrides)
  end

  # ------------------------------------------------------------ discovery

  test "discovery names the endpoints and only what the Clubhouse does" do
    get sso_discovery_path

    assert_response :success
    doc = response.parsed_body
    assert_equal "http://www.example.com", doc["issuer"]
    assert_equal "http://www.example.com/sso/authorize", doc["authorization_endpoint"]
    assert_equal "http://www.example.com/sso/token", doc["token_endpoint"]
    assert_equal "http://www.example.com/sso/userinfo", doc["userinfo_endpoint"]
    assert_equal ["code"], doc["response_types_supported"]
    assert_equal ["authorization_code"], doc["grant_types_supported"]
    assert_equal %w[client_secret_post client_secret_basic], doc["token_endpoint_auth_methods_supported"]
    assert_nil doc["code_challenge_methods_supported"]
    assert_nil doc["id_token_signing_alg_values_supported"]
  end

  # ---------------------------------------------------------------- token

  test "a code and the client's credentials are traded for a token that opens userinfo" do
    assert_difference "ActionLog.where(event: 'oauth2-token-grant', person_id: @person.id).count", 1 do
      post sso_token_path, params: token_params
    end

    assert_response :success
    assert_equal "no-store", response.headers["Cache-Control"]
    body = response.parsed_body
    assert_equal "Bearer", body["token_type"]
    assert_equal Person::SSO_ACCESS_TOKEN_LIFETIME.to_i, body["expires_in"]

    get sso_userinfo_path, headers: { "Authorization" => "Bearer #{body["access_token"]}" }

    assert_response :success
    claims = response.parsed_body
    assert_equal %w[sub chid username email given_name family_name], claims.keys
    assert_equal @person.id, claims["chid"]
    assert_equal @person.id.to_s, claims["sub"]
    assert_equal @person.email, claims["email"]
    assert_equal @person.callsign, claims["family_name"]
    assert_equal "Ranger", claims["given_name"]
  end

  test "the credentials may come as HTTP Basic instead of form fields" do
    credentials = ActionController::HttpAuthentication::Basic.encode_credentials(@client.client_id, fixture_secret(@client))

    post sso_token_path, params: token_params.except(:client_id, :client_secret),
                         headers: { "Authorization" => credentials }

    assert_response :success
    assert_equal "Bearer", response.parsed_body["token_type"]
  end

  test "a code is good once" do
    post sso_token_path, params: token_params
    assert_response :success

    post sso_token_path, params: token_params

    assert_response :bad_request
    assert_equal "invalid_grant", response.parsed_body["error"]
  end

  test "a code past its time is refused and taken away" do
    travel (OauthCode::EXPIRE_IN_SECONDS + 1).seconds do
      post sso_token_path, params: token_params
    end

    assert_response :bad_request
    assert_equal "invalid_grant", response.parsed_body["error"]
    assert_not OauthCode.exists?(@code.id)
  end

  test "another client cannot redeem the code, and does not burn it" do
    other = oauth_client(:osticket)

    post sso_token_path, params: token_params(client_id: other.client_id, client_secret: fixture_secret(other),
                                               redirect_uri: other.redirect_uri)

    assert_response :bad_request
    assert_equal "invalid_grant", response.parsed_body["error"]
    assert OauthCode.exists?(@code.id)
  end

  test "a wrong secret is refused and logged without the secret" do
    post sso_token_path, params: token_params(client_secret: "not-the-secret")

    assert_response :unauthorized
    assert_equal "invalid_client", response.parsed_body["error"]
    entry = ErrorLog.where(error_type: "oauth2-invalid-client").last
    assert_not_nil entry
    assert_equal @client.client_id, entry.data["client_id"]
    assert OauthCode.exists?(@code.id)
  end

  test "a secret that is not text is refused, not crashed on" do
    post sso_token_path, params: token_params(client_secret: ["x"])
    assert_response :unauthorized
    assert_equal "invalid_client", response.parsed_body["error"]

    post sso_token_path, params: token_params(client_secret: { a: "b" })
    assert_response :unauthorized
  end

  test "Basic credentials that are not readable text are refused and still logged" do
    credentials = "Basic #{Base64.strict_encode64("id\xFF:x".b)}"

    post sso_token_path, params: token_params.except(:client_id, :client_secret),
                         headers: { "Authorization" => credentials }

    assert_response :unauthorized
    assert_equal "invalid_client", response.parsed_body["error"]
    assert_equal 1, ErrorLog.where(error_type: "oauth2-invalid-client").count
  end

  test "a refused client is logged with its address and without the secret it tried" do
    post sso_token_path, params: token_params(client_secret: "not-the-secret")

    entry = ErrorLog.where(error_type: "oauth2-invalid-client").last
    assert_equal "127.0.0.1", entry.ip
    assert_equal "not-the-secret", entry.data.dig("parameters", "client_secret")
    assert_equal @code.code, entry.data.dig("parameters", "code")
  end

  test "a token request without the return address is refused" do
    post sso_token_path, params: token_params.except(:redirect_uri)

    assert_response :bad_request
    assert_equal "invalid_grant", response.parsed_body["error"]
    assert OauthCode.exists?(@code.id)
  end

  test "an unknown client is refused" do
    post sso_token_path, params: token_params(client_id: "no one")

    assert_response :unauthorized
    assert_equal "invalid_client", response.parsed_body["error"]
  end

  test "a return address other than the recorded one is refused" do
    post sso_token_path, params: token_params(redirect_uri: "https://elsewhere.example.org/cb")

    assert_response :bad_request
    assert_equal "invalid_grant", response.parsed_body["error"]
  end

  test "only the authorization code grant is offered" do
    post sso_token_path, params: token_params(grant_type: "password")

    assert_response :bad_request
    assert_equal "unsupported_grant_type", response.parsed_body["error"]
  end

  test "the token endpoint answers POST only" do
    get "/sso/token", params: token_params

    assert_response :not_found
  end

  # ------------------------------------------------------------- userinfo

  test "userinfo without a token, or with a made-up one, is refused" do
    get sso_userinfo_path
    assert_response :unauthorized
    assert_equal 'Bearer error="invalid_token"', response.headers["WWW-Authenticate"]

    get sso_userinfo_path, headers: { "Authorization" => "Bearer made-up" }
    assert_response :unauthorized
  end

  test "a token past its hour is refused" do
    post sso_token_path, params: token_params
    token = response.parsed_body["access_token"]

    travel Person::SSO_ACCESS_TOKEN_LIFETIME + 1.minute do
      get sso_userinfo_path, headers: { "Authorization" => "Bearer #{token}" }
    end

    assert_response :unauthorized
  end

  test "someone who is not an active Ranger is named by status" do
    prospective = person(:prospective_ranger)

    get sso_userinfo_path, headers: { "Authorization" => "Bearer #{prospective.generate_token_for(:sso_access)}" }

    assert_response :success
    assert_equal "Prospective", response.parsed_body["given_name"]
  end

  # ----------------------------------------------------------------- mode

  test "everything here answers whatever the variable says" do
    [nil, Sso::CLIENT].each do |mode|
      set_sso_mode(mode)
      @code = OauthCode.issue(@client, @person, Sso::SCOPE)

      get sso_discovery_path
      assert_response :success

      post sso_token_path, params: token_params
      assert_response :success

      get sso_userinfo_path, headers: { "Authorization" => "Bearer #{@person.generate_token_for(:sso_access)}" }
      assert_response :success
    end
  end
end
