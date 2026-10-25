# frozen_string_literal: true

# The pages of single sign-on. As a server, the moment a signed-in person is
# handed back to the website that sent them. As a client, the trip out to the
# Clubhouse that holds the accounts, and the return with a code.
#
# The calls a website makes directly (token, userinfo) live in
# Sso::ApiController. Which pages answer at all is decided by the routes.
class SsoController < ApplicationController
  layout "sessions"

  allow_unauthenticated_access only: %i[login callback]
  before_action :redirect_if_authenticated, only: %i[login callback]

  # Each return costs a call to the other Clubhouse, so the trip is capped
  # the way the password form is.
  rate_limit to: 10, within: 45.seconds, only: %i[login callback],
             with: -> { redirect_to root_path, alert: "Try again later." }

  # Kept in the session between the trip out and the return, so a code
  # arriving from anywhere but the sign-in this browser started is refused.
  STATE_KEY = :sso_state

  # Server. A website sends a signed-in person here with its client id and the
  # address it wants them back at. Both have to match a recorded client, or
  # nothing is handed out and the page says so.
  def authorize
    client = OauthClient.find_by(client_id: params[:client_id].to_s)
    unless client && authorize_request_valid?(client)
      ErrorLog.record("oauth2-invalid-request", data: { client_id: params[:client_id] }, request: request)
      render :invalid_request, status: :unprocessable_entity
      return
    end

    code = OauthCode.issue(client, current_user, params[:scope])
    @client = client
    @callback_url = callback_url_for(client, code, params[:redirect_uri])
    render :hand_back
  end

  # Client. Start the trip out. The state is kept until a return spends it,
  # so a second tab, or a second tap on a slow link, does not strand the
  # first trip with a state the session no longer holds.
  def login
    state = session[STATE_KEY] ||= SecureRandom.hex(16)
    redirect_to Sso::Client.new.authorize_url(state: state, redirect_uri: sso_callback_url),
                allow_other_host: true
  end

  # Client. Back from the other Clubhouse with a code and the state that left.
  def callback
    expected = session.delete(STATE_KEY).to_s
    unless expected.present? && ActiveSupport::SecurityUtils.secure_compare(expected, params[:state].to_s)
      return sign_in_failed("Sign-in didn't complete. Try again.")
    end
    return sign_in_failed("The Clubhouse didn't sign you in. Try again.") if params[:code].blank?

    person = Person.find_by(id: Sso::Client.new.exchange(params[:code].to_s, redirect_uri: sso_callback_url))
    unless person
      ErrorLog.record("oauth2-unknown-person", request: request)
      return sign_in_failed("No Clubhouse account matches that sign-in.")
    end
    return sign_in_failed(locked_account_message, status: :forbidden) if sign_in_refused?(person)

    start_new_session_for person
    redirect_to after_authentication_url
  rescue Sso::Client::Error => e
    ErrorLog.record_exception(e, "oauth2-client-failed", request: request)
    sign_in_failed("The Clubhouse sign-in service didn't answer. Try again in a moment.",
                   status: :bad_gateway)
  end

  private

  # Every value the website sent has to be a plain string of the right shape
  # before anything is stored or put on an address: the scope column is
  # SCOPE_LIMIT wide, and a state that is not text cannot be sent back.
  SCOPE_LIMIT = 255

  def authorize_request_valid?(client)
    params[:response_type] == "code" &&
      params[:scope].is_a?(String) && params[:scope].length.between?(1, SCOPE_LIMIT) &&
      (params[:state].nil? || params[:state].is_a?(String)) &&
      client.accepts_redirect_uri?(params[:redirect_uri])
  end

  # The code and, when the website sent one, its state, on the recorded address.
  def callback_url_for(client, code, redirect_uri)
    query = { code: code.code, state: params[:state].presence }.compact.to_query
    "#{redirect_uri}#{client.redirect_uri.include?("?") ? "&" : "?"}#{query}"
  end

  # The sign-in page again, with the reason on it rather than in a toast that
  # would be gone before it was read.
  def sign_in_failed(message, status: :unprocessable_entity)
    @sso_error = message
    render "sessions/new", status: status
  end
end
