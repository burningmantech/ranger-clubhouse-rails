# frozen_string_literal: true

require "test_helper"

# The pages of single sign-on: the server's hand-back of a signed-in person,
# and the client's trip out and return.
class SsoControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include SsoTestHelper

  setup do
    OauthCode.delete_all
    ErrorLog.delete_all
    @client = oauth_client(:moodle)
    @person = person(:active_ranger)
  end

  def grant_params(**overrides)
    { response_type: "code", client_id: @client.client_id, redirect_uri: @client.redirect_uri,
      scope: Sso::SCOPE, state: "xyz" }.merge(overrides)
  end

  # ------------------------------------------------------ server: authorize

  test "a signed-in person is handed back with a code and the state that came in" do
    set_sso_mode(Sso::SERVER)
    sign_in_as(@person)

    assert_difference "OauthCode.count", 1 do
      get sso_authorize_path, params: grant_params
    end

    assert_response :success
    code = OauthCode.last
    assert_equal @person.id, code.person_id
    assert_equal @client.id, code.oauth_client_id
    assert_equal Sso::SCOPE, code.scope
    # The row keeps only a digest of the code: the page is where the code is.
    assert_equal OauthCode.digest(issued_code), code.code_digest
    expected = "#{@client.redirect_uri}?code=#{issued_code}&state=xyz"
    assert_equal expected, continue_link
    assert_select "meta[http-equiv=refresh][content=?]", "0;url=#{expected}"
    assert_select "a[href=?]", expected, text: /Continue to #{Regexp.escape(@client.description)}/
    assert_select "[role=status]", text: /Sending you back to #{Regexp.escape(@client.description)}/
  end

  test "a state that was not sent is not sent back" do
    set_sso_mode(Sso::SERVER)
    sign_in_as(@person)

    get sso_authorize_path, params: grant_params.except(:state)

    assert_response :success
    assert_equal "#{@client.redirect_uri}?code=#{issued_code}", continue_link
    assert_equal OauthCode.digest(issued_code), OauthCode.last.code_digest
  end

  test "someone not signed in is sent to sign in, and this page is where they come back to" do
    set_sso_mode(Sso::SERVER)

    get sso_authorize_path, params: grant_params

    assert_redirected_to root_path
    assert_match %r{/sso/authorize\?}, request.session[:return_to_after_authenticating]
    assert_equal 0, OauthCode.count
  end

  test "a return address other than the recorded one gets no code" do
    set_sso_mode(Sso::SERVER)
    sign_in_as(@person)

    assert_no_difference "OauthCode.count" do
      get sso_authorize_path, params: grant_params(redirect_uri: "https://elsewhere.example.org/cb")
    end

    assert_response :unprocessable_entity
    assert_select "h1", text: /Something Went Wrong/
    assert_equal 1, ErrorLog.where(error_type: "oauth2-invalid-request").count
  end

  test "a client whose return address is not yet recorded gets a code, whatever address it names" do
    set_sso_mode(Sso::SERVER)
    sign_in_as(@person)
    @client.update_column(:redirect_uri, "")

    assert_difference "OauthCode.count", 1 do
      get sso_authorize_path, params: grant_params(redirect_uri: "https://anywhere.example.org/cb")
    end

    assert_response :success
  end

  {
    "an unknown client" => { client_id: "no one" },
    "a response type other than code" => { response_type: "token" },
    "no scope" => { scope: "" },
    "a scope longer than the column" => { scope: "a" * 256 },
    "a scope that is not text" => { scope: ["openid"] },
    "a state that is not text" => { state: { a: "b" } }
  }.each do |description, overrides|
    test "#{description} gets no code" do
      set_sso_mode(Sso::SERVER)
      sign_in_as(@person)

      assert_no_difference "OauthCode.count" do
        get sso_authorize_path, params: grant_params(**overrides)
      end

      assert_response :unprocessable_entity
    end
  end

  test "a person locked while signed in is signed out and handed nothing" do
    set_sso_mode(Sso::SERVER)
    sign_in_as(@person)
    @person.update_columns(status: Person::SUSPENDED)

    assert_no_difference "OauthCode.count" do
      get sso_authorize_path, params: grant_params
    end

    assert_redirected_to root_path
    assert_not Session.exists?(@test_session.id)
  end

  test "the hand-back page answers whatever the variable says" do
    [nil, Sso::CLIENT].each do |mode|
      set_sso_mode(mode)
      sign_in_as(@person)

      get sso_authorize_path, params: grant_params

      assert_response :success
    end
  end

  # --------------------------------------------------------------- client

  test "a second trip out keeps the state of the first, so either return is honoured" do
    set_sso_mode(Sso::CLIENT)

    get sso_login_path
    first = Rack::Utils.parse_query(URI.parse(response.location).query)["state"]
    get sso_login_path
    second = Rack::Utils.parse_query(URI.parse(response.location).query)["state"]

    assert_equal first, second
    assert_equal first, request.session[:sso_state]
  end

  test "login sends the person to the other Clubhouse with a state kept for the return" do
    set_sso_mode(Sso::CLIENT)

    get sso_login_path

    assert_response :redirect
    location = URI.parse(response.location)
    assert_equal "clubhouse.example.org", location.host
    assert_equal "/sso/authorize", location.path
    query = Rack::Utils.parse_query(location.query)
    assert_equal "clubhouse3", query["client_id"]
    assert_equal sso_callback_url, query["redirect_uri"]
    assert_equal "code", query["response_type"]
    assert_equal query["state"], request.session[:sso_state]
    assert_operator query["state"].length, :>=, 32
  end

  test "coming back with the code signs the person in" do
    set_sso_mode(Sso::CLIENT)
    stub_exchange(chid: @person.id)
    get sso_login_path
    state = request.session[:sso_state]

    assert_difference ["Session.where(person_id: @person.id).count",
                       "ActionLog.where(event: 'auth-login', person_id: @person.id).count"], 1 do
      get sso_callback_path, params: { code: "the-code", state: state }
    end

    assert_redirected_to me_root_path
    assert_nil request.session[:sso_state]
    assert cookies[:session_id].present?
  end

  test "coming back lands on the page that was asked for before signing in" do
    set_sso_mode(Sso::CLIENT)
    stub_exchange(chid: @person.id)
    get me_profile_path
    assert_redirected_to root_path
    get sso_login_path

    get sso_callback_path, params: { code: "the-code", state: request.session[:sso_state] }

    assert_redirected_to me_profile_url
  end

  test "a return with the wrong state is refused" do
    set_sso_mode(Sso::CLIENT)
    stub_exchange(chid: @person.id)
    get sso_login_path

    assert_no_difference "Session.count" do
      get sso_callback_path, params: { code: "the-code", state: "somebody-elses" }
    end

    assert_response :unprocessable_entity
  end

  test "a return with no state at all is refused" do
    set_sso_mode(Sso::CLIENT)
    stub_exchange(chid: @person.id)

    get sso_callback_path, params: { code: "the-code", state: "" }

    assert_response :unprocessable_entity
  end

  test "a return without a code is refused" do
    set_sso_mode(Sso::CLIENT)
    get sso_login_path

    get sso_callback_path, params: { state: request.session[:sso_state], error: "access_denied" }

    assert_response :unprocessable_entity
  end

  test "a person the other Clubhouse names but this database lacks is refused" do
    set_sso_mode(Sso::CLIENT)
    stub_exchange(chid: Person.maximum(:id) + 1000)
    get sso_login_path

    get sso_callback_path, params: { code: "the-code", state: request.session[:sso_state] }

    assert_response :unprocessable_entity
    assert_equal 1, ErrorLog.where(error_type: "oauth2-unknown-person").count
  end

  test "a locked person the other Clubhouse names is refused here too" do
    set_sso_mode(Sso::CLIENT)
    @person.update_columns(status: Person::DECEASED)
    stub_exchange(chid: @person.id)
    get sso_login_path

    assert_no_difference "Session.count" do
      get sso_callback_path, params: { code: "the-code", state: request.session[:sso_state] }
    end

    assert_response :forbidden
    assert_equal 1, ActionLog.where(event: "auth-failed", person_id: @person.id).count
  end

  test "a Clubhouse that cannot be reached is refused and logged, not an error page" do
    set_sso_mode(Sso::CLIENT)
    stub_sso_unreachable
    get sso_login_path

    get sso_callback_path, params: { code: "the-code", state: request.session[:sso_state] }

    assert_response :bad_gateway
    assert_equal 1, ErrorLog.where(error_type: "oauth2-client-failed").count
  end

  test "someone already signed in is sent to their dashboard instead of out again" do
    set_sso_mode(Sso::CLIENT)
    sign_in_as(@person)

    get sso_login_path
    assert_redirected_to me_root_path

    get sso_callback_path, params: { code: "c", state: "s" }
    assert_redirected_to me_root_path
  end

  test "the client pages answer whatever the variable says" do
    [nil, Sso::SERVER].each do |mode|
      set_sso_mode(mode)

      get sso_login_path
      assert_response :redirect

      get sso_callback_path, params: { code: "c", state: "s" }
      assert_response :unprocessable_entity
    end
  end

  private

  # Where the authorize page sends the person back to: the one link to the
  # client, as the page spells it.
  def continue_link
    links = css_select("a[href^=\"#{@client.redirect_uri}\"]")
    assert_equal 1, links.size, "one link back to the client"
    links.first["href"]
  end

  def issued_code
    Rack::Utils.parse_query(URI(continue_link).query).fetch("code")
  end

  def stub_exchange(chid:)
    stub_sso_transport(token: [200, { access_token: "tok", token_type: "Bearer" }.to_json],
                       userinfo: [200, { chid: chid }.to_json])
  end
end
