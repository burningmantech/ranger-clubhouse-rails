# frozen_string_literal: true

require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  include ExceptionRenderingTestHelper
  include SsoTestHelper
  include PasskeyTestHelper
  include EmailSuppressionTestHelper

  setup do
    @person = person(:active_ranger)
    @person.password = "password"
    @person.save!(validate: false)
  end

  # --- GET / ---

  test "login renders sign-in form with login_form scoped email and password fields" do
    get root_path
    assert_response :success
    assert_select "form" do
      assert_select "input[name='login_form[email]']"
      assert_select "input[name='login_form[password]']"
    end
  end

  test "the door: a one-line beta notice, the mark, the forgot link beside the password, a show-password button, and the other ways in" do
    get root_path

    assert_response :success
    assert_select ".login-beta details summary", text: /Clubhouse 3 Beta\. Nothing here reaches production\. No email or SMS is sent\./
    assert_select ".login-beta details[open]", count: 0
    assert_select ".login-beta dl.instruction-list dt", text: "Does anything here reach production?"
    assert_select ".login-backdrop[aria-hidden=true]"
    assert_select ".login-mark", count: 0
    assert_select ".login-label-row label[for=login_form_password]", text: "Password"
    assert_select ".login-label-row a[href='#{forgot_path}']", text: "Forgot it?"
    assert_select "[data-controller=password-reveal]" do
      assert_select "input[type=password][data-password-reveal-target=input]"
      assert_select "button[type=button][aria-pressed=false][aria-label='Show password']" \
                    "[data-action='password-reveal#toggle']" do
        assert_select "[data-password-reveal-target=show]:not(.hidden) i.fa-eye"
        assert_select "[data-password-reveal-target=hide].hidden i.fa-eye-slash"
      end
    end
    assert_select ".login-status", text: /until The Man burns|burns tonight|next burn/
    assert_select ".login-column .login-columns > .login-panel + nav.login-doors h2", text: "Audit Training? Want to be a Ranger?"
    assert_select ".login-doors a[href='#{register_path}']", text: "Auditing a Training? Create an Account"
    assert_select ".login-doors a[href='mailto:#{EmailAddresses::VOLUNTEER_COORDINATORS_TEAM}']"
    assert_select ".login-doors a[href='mailto:#{EmailAddresses::TECH_CADRE}']"
  end

  test "login form does not use nested scope for fields" do
    get root_path
    assert_response :success
    assert_select "input[name='session[email]']", count: 0
    assert_select "input[name='session[password]']", count: 0
  end

  # --- POST / ---

  test "successful login records an auth-login action" do
    assert_difference -> { ActionLog.where(event: "auth-login", person_id: @person.id).count } do
      post root_path, params: { login_form: { email: @person.email, password: "password" } }
    end
    assert_redirected_to me_root_path
  end

  test "failed login does not record an auth-login action" do
    assert_no_difference -> { ActionLog.where(event: "auth-login").count } do
      post root_path, params: { login_form: { email: @person.email, password: "wrong" } }
    end
    assert_response :unprocessable_entity
  end

  # --- GET /forgot ---

  test "forgot renders for unauthenticated user" do
    get forgot_path
    assert_response :success
    assert_select "form"
    assert_select "input[name='password_reset_form[email]']"
  end

  # --- POST /reset-password ---

  test "reset_password with invalid params renders forgot with unprocessable_entity" do
    post reset_password_path, params: {
      password_reset_form: { email: "not-an-email" }
    }
    assert_response :unprocessable_entity
  end

  test "reset_password with valid email renders neutral confirmation" do
    post reset_password_path, params: {
      password_reset_form: { email: @person.email }
    }
    assert_response :success
    assert_select "h1", text: /check your email/i
  end

  test "reset_password with non-existent email still renders neutral confirmation" do
    post reset_password_path, params: {
      password_reset_form: { email: "no one@example.com" }
    }
    assert_response :unprocessable_entity
  end

  test "reset_password sends email for existing user" do
    assert_emails 1 do
      post reset_password_path, params: {
        password_reset_form: { email: @person.email }
      }
    end
  end

  test "reset_password does not send email for non-existent user" do
    assert_no_emails do
      post reset_password_path, params: {
        password_reset_form: { email: "no one@example.com" }
      }
    end
  end

  # SuppressedRecipientsInterceptor drops the address; the page says the same
  # as for any other account.
  test "reset_password for a suppressed address renders the confirmation and sends nothing" do
    suppress_email(@person.email)

    assert_no_emails do
      post reset_password_path, params: {
        password_reset_form: { email: @person.email }
      }
    end
    assert_response :success
    assert_select "h1", text: /check your email/i
  end

  test "reset_password renders confirmation even when mailer raises" do
    # Make deliver_now raise by temporarily replacing the mailer method
    raising_message = Object.new
    raising_message.define_singleton_method(:deliver_now) { raise StandardError, "SMTP down" }

    original_method = PasswordResetMailer.method(:notify)
    PasswordResetMailer.define_singleton_method(:notify) { |**_args| raising_message }

    with_exceptions_rendered do
      post reset_password_path, params: {
        password_reset_form: { email: @person.email }
      }

      assert_response :internal_server_error
    end
  ensure
    PasswordResetMailer.define_singleton_method(:notify, original_method)
  end

  # --- GET /reset-token ---

  test "reset_token with missing token redirects to forgot" do
    get reset_token_path
    assert_redirected_to forgot_path
    assert_match(/invalid or has expired/i, flash[:alert])
  end

  test "reset_token with invalid token redirects to forgot" do
    get reset_token_path(token: "bogus")
    assert_redirected_to forgot_path
    assert_match(/invalid or has expired/i, flash[:alert])
  end

  test "reset_token with expired token redirects to forgot" do
    token = @person.create_temporary_login_token
    @person.update_columns(tpassword_expire: 1.hour.ago.to_i)

    get reset_token_path(token: token)
    assert_redirected_to forgot_path
    assert_match(/invalid or has expired/i, flash[:alert])
  end

  test "reset_token with valid token renders reset form" do
    token = @person.create_temporary_login_token

    get reset_token_path(token: token)
    assert_response :success
    assert_select "form"
    assert_select "input[name='password_update_form[token]'][type='hidden']"
    assert_select "input[name='password_update_form[password]']"
    assert_select "input[name='password_update_form[password_confirmation]']"
  end

  # --- POST /update-password ---

  test "update_password with invalid form rerenders reset_token" do
    token = @person.create_temporary_login_token

    post update_password_path, params: {
      password_update_form: { token: token, password: "short", password_confirmation: "short" }
    }
    assert_response :unprocessable_entity
  end

  test "update_password with mismatched confirmation rerenders reset_token" do
    token = @person.create_temporary_login_token

    post update_password_path, params: {
      password_update_form: { token: token, password: "newpassword1", password_confirmation: "different1" }
    }
    assert_response :unprocessable_entity
  end

  test "update_password with expired token redirects to forgot" do
    token = @person.create_temporary_login_token
    @person.update_columns(tpassword_expire: 1.hour.ago.to_i)

    post update_password_path, params: {
      password_update_form: { token: token, password: "newpassword1", password_confirmation: "newpassword1" }
    }
    assert_redirected_to forgot_path
    assert_match(/invalid or has expired/i, flash[:error])
  end

  test "update_password with invalid token redirects to forgot" do
    post update_password_path, params: {
      password_update_form: { token: "bogus", password: "newpassword1", password_confirmation: "newpassword1" }
    }
    assert_redirected_to forgot_path
  end

  test "update_password with valid token updates password and redirects to login" do
    token = @person.create_temporary_login_token

    post update_password_path, params: {
      password_update_form: { token: token, password: "mynewpassword", password_confirmation: "mynewpassword" }
    }
    assert_redirected_to me_root_path
    assert_match(/password has been reset/i, flash[:notice])

    @person.reload
    assert @person.authenticate("mynewpassword"), "New password should work"
    assert_not @person.authenticate("password"), "Old password should not work"
  end

  test "update_password clears temporary token after success" do
    token = @person.create_temporary_login_token

    post update_password_path, params: {
      password_update_form: { token: token, password: "mynewpassword", password_confirmation: "mynewpassword" }
    }

    @person.reload
    # Person#password= clears tpassword and tpassword_expire
    assert_equal "", @person.tpassword
    assert_equal 0, @person.tpassword_expire
  end

  # --- the welcome email's link (welcome=1) ---

  WELCOME_LINK_FAILED = "The welcome link was already used or has expired. If you already set your password, " \
                        "sign in with it. If not, request a reset link here."

  test "reset_token with welcome reads as a welcome and carries the flag into the form" do
    token = @person.create_temporary_login_token

    get reset_token_path(token:, welcome: 1)
    assert_response :success
    assert_select "title", "Welcome | Ranger Secret Clubhouse"
    assert_select "h1", text: "Welcome to the Ranger Secret Clubhouse"
    assert_select "header p", text: "The first step is to set a password for your Clubhouse account."
    assert_select "input[type='submit'][value='Set Password'][aria-label='Set password for your Clubhouse account']"
    assert_select "input[name='password_update_form[welcome]'][type='hidden']"
    assert_select "input[name='password_update_form[token]'][type='hidden'][value='#{token}']"
  end

  test "reset_token without welcome reads as a reset" do
    token = @person.create_temporary_login_token

    get reset_token_path(token:)
    assert_response :success
    assert_select "title", "Set New Password | Ranger Secret Clubhouse"
    assert_select "h1", text: "Set New Password"
    assert_select "header p", text: "Choose a new password for your account."
    assert_select "input[type='submit'][value='Reset Password'][aria-label='Set your new password']"
    assert_select "input[name='password_update_form[welcome]']", count: 0
  end

  test "update_password with welcome and a mismatched confirmation rerenders the welcome" do
    token = @person.create_temporary_login_token

    post update_password_path, params: {
      password_update_form: { token:, password: "newpassword1", password_confirmation: "different1", welcome: "true" }
    }
    assert_response :unprocessable_entity
    assert_select "h1", text: "Welcome to the Ranger Secret Clubhouse"
    assert_select "input[name='password_update_form[welcome]'][type='hidden']"
  end

  test "update_password with welcome sets the password and says welcome" do
    token = @person.create_temporary_login_token

    post update_password_path, params: {
      password_update_form: { token:, password: "mynewpassword", password_confirmation: "mynewpassword", welcome: "true" }
    }
    assert_redirected_to me_root_path
    assert_equal "Your password is set. Welcome to the Clubhouse!", flash[:notice]
    assert @person.reload.authenticate("mynewpassword"), "New password should work"
  end

  test "an expired welcome link sends its reader to Forgot with the welcome message" do
    token = @person.create_temporary_login_token
    @person.update_columns(tpassword_expire: 1.hour.ago.to_i)

    get reset_token_path(token:, welcome: 1)
    assert_redirected_to forgot_path
    assert_equal WELCOME_LINK_FAILED, flash[:alert]

    post update_password_path, params: {
      password_update_form: { token:, password: "newpassword1", password_confirmation: "newpassword1", welcome: "true" }
    }
    assert_redirected_to forgot_path
    assert_equal WELCOME_LINK_FAILED, flash[:error]
  end

  # --- signing in with a passkey ---

  test "the sign-in page offers a passkey, hidden until the script finds a browser that can" do
    get root_path

    assert_response :success
    assert_select "[data-controller=passkey][hidden][data-passkey-ceremony-value=get]" \
                  "[data-passkey-options-url-value='#{passkey_options_path}']" do
      assert_select "button[type=button][data-action='passkey#run']", text: /Sign In with a Passkey/
      assert_select "form[action='#{passkey_sign_in_path}'][data-turbo=false] input[type=hidden][name=credential]"
      assert_select "[data-passkey-target=error][hidden]"
    end
    # Still one primary action: the password form's own button.
    assert_select "input[type=submit][value='Sign In']", count: 1
  end

  test "the options for a passkey sign-in name no account and demand the fingerprint, face or PIN" do
    post passkey_options_path

    assert_response :success
    options = response.parsed_body
    assert_predicate options["challenge"], :present?
    assert_equal "www.example.com", options["rpId"]
    assert_equal "required", options["userVerification"]
    assert_empty options["allowCredentials"]
    assert_equal options["challenge"], session[Passkeys::Authentication::SESSION_KEY]["challenge"]
  end

  test "a passkey signs its owner in, and the login line says which passkey" do
    passkey = register_passkey_for(@person)

    # The Rails session store shares the sessions table, so count the person's
    # own sign-ins rather than every row.
    assert_difference -> { Session.where(person_id: @person.id).count }, 1 do
      freeze_time do
        post passkey_sign_in_path, params: { credential: passkey_assertion_for(passkey_sign_in_options, sign_count: 1) }

        assert_equal Time.current, passkey.reload.last_used_at
      end
    end

    assert_redirected_to me_root_path
    assert_equal 1, passkey.sign_count
    entry = ActionLog.where(event: "auth-login", person_id: @person.id).last
    assert_equal passkey.id, entry.data["passkey_id"]
  end

  test "a password sign-in leaves the login line as it always was" do
    post root_path, params: { login_form: { email: @person.email, password: "password" } }

    assert_nil ActionLog.where(event: "auth-login", person_id: @person.id).last.data
  end

  test "a passkey sign-in goes on to the page that asked for it" do
    register_passkey_for(@person)
    get me_profile_path
    assert_redirected_to root_path

    post passkey_sign_in_path, params: { credential: passkey_assertion_for(passkey_sign_in_options) }

    assert_redirected_to me_profile_url
  end

  test "a passkey sign-in hands a single sign-on request back to where it came from" do
    register_passkey_for(@person)

    with_sso_mode(Sso::SERVER) do
      get sso_authorize_path(client_id: "moodle", response_type: "code", state: "abc")
      assert_redirected_to root_path

      post passkey_sign_in_path, params: { credential: passkey_assertion_for(passkey_sign_in_options) }

      assert_redirected_to sso_authorize_url(client_id: "moodle", response_type: "code", state: "abc")
    end
  end

  test "a device naming the account it filed the passkey under must name the right one" do
    register_passkey_for(@person)

    post passkey_sign_in_path,
         params: { credential: passkey_assertion_for(passkey_sign_in_options, user_handle: @person.id.to_s) }
    assert_redirected_to me_root_path
  end

  test "a device naming some other account is refused" do
    register_passkey_for(@person)

    assert_passkey_refused do
      post passkey_sign_in_path,
           params: { credential: passkey_assertion_for(passkey_sign_in_options, user_handle: person(:auditor_ranger).id.to_s) }
    end
  end

  test "a passkey the Clubhouse no longer holds is refused, and the page says what to do instead" do
    register_passkey_for(@person).destroy

    assert_passkey_refused do
      post passkey_sign_in_path, params: { credential: passkey_assertion_for(passkey_sign_in_options) }
    end
    assert_select "input[name='login_form[email]']"
  end

  # Clubhouse 2 shares the database and can delete a person without knowing
  # the passkey table exists.
  test "a passkey whose account is gone is refused like any unknown passkey" do
    register_passkey_for(@person).update_columns(person_id: Person.maximum(:id) + 1)

    assert_passkey_refused do
      post passkey_sign_in_path, params: { credential: passkey_assertion_for(passkey_sign_in_options) }
    end
  end

  test "a passkey answering from another website is refused, and the reason is recorded" do
    ErrorLog.delete_all
    device = WebAuthn::FakeClient.new("https://clubhouse.example.net")
    passkey = register_passkey_for(@person, device: WebAuthn::FakeClient.new(PasskeyTestHelper::REQUEST_ORIGIN,
                                                                           authenticator: device.send(:authenticator)))

    assert_passkey_refused do
      post passkey_sign_in_path,
           params: { credential: passkey_assertion_for(passkey_sign_in_options, device: device, rp_id: "www.example.com") }
    end

    entry = ErrorLog.where(error_type: "passkey-sign-in-refused").last
    assert_equal "WebAuthn::OriginVerificationError", entry.data["reason"]
    assert_equal passkey.id, entry.data["passkey_id"]
    assert_equal @person.id, entry.data["person_id"]
  end

  # The one failure that can mean a copied security key.
  test "a counter that went backwards is refused and recorded under its own name" do
    ErrorLog.delete_all
    passkey = register_passkey_for(@person)
    passkey.update_columns(sign_count: 100)

    assert_passkey_refused do
      post passkey_sign_in_path, params: { credential: passkey_assertion_for(passkey_sign_in_options, sign_count: 5) }
    end

    assert_equal 100, passkey.reload.sign_count
    assert_nil passkey.last_used_at
    assert_equal passkey.id, ErrorLog.where(error_type: "passkey-sign-count-regression").last.data["passkey_id"]
  end

  test "a passkey used without the fingerprint, face or PIN is refused" do
    register_passkey_for(@person)

    assert_passkey_refused do
      post passkey_sign_in_path,
           params: { credential: passkey_assertion_for(passkey_sign_in_options, user_verified: false) }
    end
  end

  test "an answer with no challenge behind it, an old one, or a used one has to start again" do
    register_passkey_for(@person)

    assert_passkey_refused(/That took too long/) do
      post passkey_sign_in_path, params: { credential: "{}" }
    end

    options = passkey_sign_in_options
    travel 6.minutes do
      assert_passkey_refused(/That took too long/) do
        post passkey_sign_in_path, params: { credential: passkey_assertion_for(options) }
      end
    end

    # What just failed took the challenge with it; a good answer to it is too late as well.
    assert_passkey_refused(/That took too long/) do
      post passkey_sign_in_path, params: { credential: passkey_assertion_for(options) }
    end
  end

  # The library raises whatever its parsers raise when handed bytes it cannot
  # read. None of it may become an error page.
  test "a forged or mangled passkey answer is refused, not an error page" do
    register_passkey_for(@person)
    good = JSON.parse(passkey_assertion_for(passkey_sign_in_options))
    forgeries = [
      "", "not json", "[]", "{}", "42",
      good.merge("id" => ["x"]).to_json,
      good.except("response").to_json,
      good.merge("response" => "x").to_json,
      good.merge("type" => "password").to_json,
      good.merge("response" => good["response"].merge("signature" => "AAAA")).to_json,
      good.merge("response" => good["response"].merge("authenticatorData" => "!!!")).to_json,
      good.merge("response" => good["response"].merge("clientDataJSON" => Base64.urlsafe_encode64("nope", padding: false))).to_json
    ]

    forgeries.each do |forgery|
      passkey_sign_in_options
      assert_passkey_refused { post passkey_sign_in_path, params: { credential: forgery } }
    end

    passkey_sign_in_options
    assert_passkey_refused { post passkey_sign_in_path, params: { credential: ["x"] } }
    passkey_sign_in_options
    assert_passkey_refused { post passkey_sign_in_path, params: { credential: { a: "b" } } }
  end

  test "where passkeys are off there is no passkey door and nothing behind it" do
    register_passkey_for(@person)
    switch_passkeys_off

    get root_path
    assert_select "[data-controller=passkey]", count: 0

    post passkey_options_path
    assert_response :not_found

    post passkey_sign_in_path, params: { credential: "{}" }
    assert_response :not_found
  end

  # --- locked accounts (Person::LOCKED_STATUSES) ---

  test "a locked account's right password is refused, and the refusal is logged" do
    Person::LOCKED_STATUSES.each do |status|
      @person.update_columns(status:)

      assert_locked_refused do
        post root_path, params: { login_form: { email: @person.email, password: "password" } }
      end
    end
  end

  test "a locked account's passkey is refused" do
    register_passkey_for(@person)
    @person.update_columns(status: Person::SUSPENDED)

    assert_locked_refused do
      post passkey_sign_in_path, params: { credential: passkey_assertion_for(passkey_sign_in_options) }
    end
  end

  test "a locked account is sent no reset link" do
    @person.update_columns(status: Person::DISMISSED)

    assert_no_emails do
      post reset_password_path, params: { password_reset_form: { email: @person.email } }
    end
    assert_response :forbidden
    assert_select "#form-error-summary", text: /This account has been disabled/
  end

  test "a reset link sent before the lock sets no password and signs no one in" do
    token = @person.create_temporary_login_token
    @person.update_columns(status: Person::RESIGNED)

    assert_locked_refused do
      post update_password_path, params: {
        password_update_form: { token:, password: "mynewpassword", password_confirmation: "mynewpassword" }
      }
    end
    assert @person.reload.authenticate("password")
  end

  test "a person locked while signed in is signed out on their next request" do
    post root_path, params: { login_form: { email: @person.email, password: "password" } }
    @person.update_columns(status: Person::UBERBONKED)

    assert_difference -> { Session.where(person_id: @person.id).count }, -1 do
      get me_messages_path
    end
    assert_redirected_to root_path
    assert_match(/This account has been disabled/, flash[:alert])
  end

  # --- coming back after signing in (Authentication#returnable_request?) ---

  test "a page asked for while signed out is where signing in returns to" do
    get me_announcements_path
    assert_redirected_to root_path

    post root_path, params: { login_form: { email: @person.email, password: "password" } }
    assert_redirected_to me_announcements_url
  end

  # A form post's address may answer only to a POST: Mark as Read's does, so
  # returning there after signing in would be a 404
  test "a form post made while signed out is not where signing in returns to" do
    post me_toggle_read_announcement_path(id: 1)
    assert_redirected_to root_path
    assert_nil session[:return_to_after_authenticating]

    post root_path, params: { login_form: { email: @person.email, password: "password" } }
    assert_redirected_to me_root_path
  end

  test "a frame, fetch or stream request made while signed out is not remembered" do
    get me_announcements_path, headers: { "Turbo-Frame" => "modal" }
    assert_nil session[:return_to_after_authenticating]

    get me_announcements_path, xhr: true
    assert_nil session[:return_to_after_authenticating]

    get me_announcements_path, as: :turbo_stream
    assert_nil session[:return_to_after_authenticating]
  end

  private

  def passkey_sign_in_options
    post passkey_options_path
    response.parsed_body
  end

  # Refused the way a wrong password is: the sign-in page again, the reason on
  # the form, no one signed in and no login line written.
  def assert_passkey_refused(message = /doesn't recognize that passkey/, &request)
    assert_no_difference [-> { Session.where.not(person_id: nil).count }, -> { ActionLog.where(event: "auth-login").count }], &request

    assert_response :unprocessable_entity
    assert_select "#form-error-summary", text: message
  end

  def assert_locked_refused(&request)
    assert_no_difference -> { Session.where(person_id: @person.id).count } do
      assert_difference -> { ActionLog.where(event: "auth-failed", person_id: @person.id).count }, &request
    end

    assert_response :forbidden
    assert_select "#form-error-summary", text: /This account has been disabled/
  end
end
