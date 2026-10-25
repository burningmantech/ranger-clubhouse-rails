# frozen_string_literal: true

# The calls a website makes to the Clubhouse directly, with no one at the
# keyboard: trading a sign-in code for a token, asking who the token stands
# for, and reading where those endpoints are.
#
# Built on ActionController::API on purpose. No session, no CSRF token, no
# menus, no gatekeepers: nothing here has a signed-in person, and every
# before_action ApplicationController carries would have to be skipped.
class Sso::ApiController < ActionController::API
  # A ceiling on flooding, not on guessing: a secret is 32 random characters,
  # and every sign-in through a website arrives from that website's one
  # address, so the cap has to clear a training night's rush.
  rate_limit to: 600, within: 1.minute, only: :token,
             with: -> { render json: { error: "temporarily_unavailable" }, status: :too_many_requests }

  # Where the sign-in endpoints are, for a website that reads it rather than
  # being told. Only what the Clubhouse really does is listed.
  def discovery
    render json: {
      issuer: request.base_url,
      authorization_endpoint: sso_authorize_url,
      token_endpoint: sso_token_url,
      userinfo_endpoint: sso_userinfo_url,
      response_types_supported: ["code"],
      grant_types_supported: ["authorization_code"],
      subject_types_supported: ["public"],
      scopes_supported: Sso::SCOPES,
      token_endpoint_auth_methods_supported: %w[client_secret_post client_secret_basic],
      claims_supported: Person.new.sso_claims.keys
    }
  end

  # A code plus the website's id and secret, for a token that opens userinfo.
  # The return address has to come along and match, as it did when the code
  # was handed out; every website the Clubhouse signs in for sends it.
  def token
    response.headers["Cache-Control"] = "no-store"
    return oauth_error("unsupported_grant_type") unless params[:grant_type] == "authorization_code"

    client = authenticate_client
    return unless client
    return oauth_error("invalid_grant") unless client.accepts_redirect_uri?(params[:redirect_uri])

    code = OauthCode.redeem(client, params[:code].to_s)
    return oauth_error("invalid_grant") unless code

    person = code.person
    ActionLog.record(person, "oauth2-token-grant", "token granted for #{client.client_id}", { id: client.id })
    render json: {
      token_type: "Bearer",
      access_token: person.generate_token_for(:sso_access),
      expires_in: Person::SSO_ACCESS_TOKEN_LIFETIME.to_i
    }
  end

  # Who a token stands for.
  def userinfo
    person = Person.find_by_token_for(:sso_access, bearer_token) if bearer_token.present?
    unless person
      response.headers["WWW-Authenticate"] = 'Bearer error="invalid_token"'
      return oauth_error("invalid_token", :unauthorized)
    end

    render json: person.sso_claims
  end

  private

  def oauth_error(code, status = :bad_request)
    render json: { error: code }, status: status
  end

  # The website's id and secret arrive either as form fields or as HTTP Basic
  # credentials; the learning site can send either. A refusal is logged with
  # the request: the log keeps the filtered parameters, so the secret that
  # was tried is masked, and the Authorization header is never stored.
  def authenticate_client
    client_id, secret = client_credentials
    client = OauthClient.find_by(client_id: client_id) if client_id.present?

    if client && secret.present? && client.secret == secret
      return client
    end

    ErrorLog.record("oauth2-invalid-client", data: { client_id: client_id }, request: request)
    response.headers["WWW-Authenticate"] = 'Basic realm="Clubhouse"' if request.authorization.present?
    oauth_error("invalid_client", :unauthorized)
    nil
  end

  # Both values as plain text, or nil. A form field that is not text (an
  # array, a nested value) is refused rather than crashed on, and Basic
  # credentials come back from the decoder as bytes that have to be readable
  # before they can be compared or logged.
  def client_credentials
    basic = ActionController::HttpAuthentication::Basic
    values = if basic.has_basic_credentials?(request)
               basic.user_name_and_password(request)
             else
               [params[:client_id], params[:client_secret]]
             end
    values.map { |value| value.is_a?(String) ? value.dup.force_encoding(Encoding::UTF_8).scrub : nil }
  end

  def bearer_token
    @bearer_token ||= request.authorization.to_s[/\ABearer\s+(\S+)\z/i, 1]
  end
end
