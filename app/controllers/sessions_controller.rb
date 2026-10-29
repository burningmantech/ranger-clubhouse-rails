class SessionsController < ApplicationController
  layout "sessions"

  # Signing out is open to a past prospective (ApplicationController#confine_past_prospective).
  skip_before_action :confine_past_prospective

  before_action :redirect_if_authenticated, except: [:logout]

  allow_unauthenticated_access only: %i[
    new sign_in_as create passkey_options passkey
    forgot reset_password reset_token update_password
  ]

  rate_limit to: 10, within: 45.seconds, only: %i[create passkey],
             with: -> { redirect_to root_path, alert: "Try again later." }
  # Asked for by the page's script, so the answer is one it can read.
  rate_limit to: 10, within: 45.seconds, only: :passkey_options,
             with: -> { render json: { error: "Too many tries. Wait a minute, then try again." }, status: :too_many_requests }
  rate_limit to: 5, within: 60.seconds, only: :reset_password,
             with: -> { redirect_to forgot_path, alert: "Too many reset requests. Try again later." }

  def new
    @form = LoginForm.new
  end

  def create
    @form = LoginForm.new(params.expect(login_form: [:email, :password]))
    unless @form.valid?
      render action: :new, status: :unprocessable_entity
      return
    end

    person = Person.find_by(email: @form.email.strip)
    if person&.authenticate(@form.password.strip)
      return refuse_locked(:new) if sign_in_refused?(person)

      start_new_session_for person
      redirect_to after_authentication_url
      return
    end

    # One message for both failures: separate "no such email" and "wrong password"
    # replies let anyone enumerate which Ranger emails hold accounts. It goes on the
    # form rather than the flash so ui_form renders the persistent error summary
    # and form_controller focuses it -- the flash toast dismissed itself a few
    # seconds later, leaving a failed sign-in with nothing on screen saying why.
    @form.errors.add(:base, "That email address and password don't match.")
    render :new, status: :unprocessable_entity
  end

  # Signing in with a passkey takes two requests with the device's own prompt
  # in between (Passkeys::Authentication has the rules). The page's script asks
  # for the options, and the form it then sends carries what the device answered.
  def passkey_options
    render json: passkey_authentication.start.value
  end

  def passkey
    credential = params[:credential]
    outcome = passkey_authentication.finish(credential.is_a?(String) ? credential : "")
    @form = LoginForm.new

    if outcome.ok?
      return refuse_locked(:new) if sign_in_refused?(outcome.value.person)

      start_new_session_for outcome.value.person, passkey: outcome.value
      redirect_to after_authentication_url
      return
    end

    # On the form rather than the flash, for the reason given in create.
    @form.errors.add(:base, outcome.error)
    render :new, status: :unprocessable_entity
  end

  def sign_in_as
    person = Person.retrieve_by_callsign(params.expect!(:callsign)) if Rails.env.development?
    unless person
      redirect_to root_path, alert: "No account found with that callsign."
      return
    end

    start_new_session_for person
    redirect_to me_root_path
  end

  def logout
    terminate_session
    redirect_to root_path
  end

  def forgot
    @form = PasswordResetForm.new
  end

  def reset_password
    @form = PasswordResetForm.new(password_reset_form_params)
    unless @form.valid?
      render action: :forgot, status: :unprocessable_entity
      return
    end

    person = Person.find_by(email: @form.email)
    return refuse_locked(:forgot) if person && sign_in_refused?(person)

    if person
        token = person.generate_token_for(:password_reset)
        PasswordResetMailer.notify(person:, reset_token: token).deliver_now
        render :reset_password_confirmation, status: :accepted
        return
    end

    @form.errors.add(:email, "Email address not found.")
    render action: :forgot, status: :unprocessable_entity
  end

  def reset_token
    @form = PasswordUpdateForm.new(token: params[:token], welcome: params[:welcome])
    return if find_person_by_token(params[:token])

    redirect_to forgot_path, alert: link_failed_message
  end

  def update_password
    @form = PasswordUpdateForm.new(password_update_form_params)
    unless @form.valid?
      render :reset_token, status: :unprocessable_entity
      return
    end

    person = find_person_by_token(@form.token)
    unless person
      redirect_to forgot_path, error: link_failed_message
      return
    end
    return refuse_locked(:reset_token) if sign_in_refused?(person)

    person.password = @form.password
    person.save!(validate: false)
    if Sso.client?
      # The accounts are signed in elsewhere. The new password is stored for
      # the Clubhouse that does the signing in; no one is signed in here.
      redirect_to root_path, notice: "Password reset. Sign in with the Ranger Clubhouse."
      return
    end

    start_new_session_for person
    notice = @form.welcome ? "Your password is set. Welcome to the Clubhouse!" : "Your password has been reset."
    redirect_to me_root_path, notice:
  end

  def clear_cache
    Rails.cache.clear if Rails.env.development?
    respond_to do |format|
      format.turbo_stream { render turbo_stream: ui_toast_stream("Cache cleared", :success) }
    end
  end

  private

  # On the form rather than the flash, for the reason given in create.
  def refuse_locked(view)
    @form.errors.add(:base, locked_account_message)
    render view, status: :forbidden
  end

  def passkey_authentication
    Passkeys::Authentication.new(session: session, relying_party: Passkeys.relying_party(request))
  end

  def password_reset_form_params
    params.expect(password_reset_form: [:email])
  end

  def password_update_form_params
    params.expect(password_update_form: [:token, :password, :password_confirmation, :welcome])
  end

  # Said on Forgot, where a link that failed sends its reader for a new one.
  # The welcome email's link (welcome=1) most often fails because it was used.
  def link_failed_message
    if @form.welcome
      "The welcome link was already used or has expired. If you already set your password, sign in with it. " \
        "If not, request a reset link here."
    else
      "The reset link is invalid or has expired. Request a new one."
    end
  end

  def find_person_by_token(token)
    Person.find_by_password_link(token)
  end
end
