module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :require_authentication
    helper_method :authenticated?
  end

  class_methods do
    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
    end
  end

  private
  def authenticated?
    resume_session
  end

  def require_authentication
    resume_session || request_authentication
  end

  def resume_session
    Current.session ||= find_session_by_cookie
  end

  def find_session_by_cookie
    Session.find_by(session_id: cookies.signed[:session_id]) if cookies.signed[:session_id]
  end

  def request_authentication
    session[:return_to_after_authenticating] = request.url if returnable_request?
    redirect_to root_path
  end

  # Only a page a person can come back to. After signing in, a frame request
  # would land on a bare fragment, a fetch on raw JSON or a stream, and a form
  # post on a GET of its own address, which may not exist.
  def returnable_request?
    request.get? && !turbo_frame_request? && !request.xhr? && !request.format.turbo_stream?
  end

  def after_authentication_url
    session.delete(:return_to_after_authenticating) || me_root_path
  end

  # The pages that only make sense signed out: the sign-in door, opening an
  # account, and the trip out to another Clubhouse.
  def redirect_if_authenticated
    redirect_to me_root_path if authenticated?
  end

  # passkey: the PersonPasskey that signed the person in, when one did. The
  # login line then says which, so a sign-in can be traced to the device.
  def start_new_session_for(user, passkey: nil)
    user.sessions.create!(session_id: SecureRandom.hex(32), user_agent: request.user_agent, ip_address: request.remote_ip).tap do |session|
      Current.session = session
      Current.person = user
      Current.roles_manager = RoleManager.retrieve(Current.person)
      cookies.signed.permanent[:session_id] = { value: session.session_id, httponly: true, same_site: :lax }
      ActionLog.record(user, "auth-login", nil, passkey && { passkey_id: passkey.id })
    end
  end

  def terminate_session
    Current.session.destroy
    cookies.delete(:session_id)
  end

  # A locked account (Person#locked?) is refused at every door, as Clubhouse 2's
  # UserAuthentication::loginUser refused it, and the refusal is logged under
  # Login Failures.
  def sign_in_refused?(person)
    return false unless person.locked?

    ActionLog.record(person, "auth-failed", "Account disabled")
    true
  end

  # Clubhouse 2's wording. Every door but Forgot shows it only after a correct
  # password, passkey or link.
  def locked_account_message
    "This account has been disabled and can't be signed into. " \
      "Contact the Ranger Personnel Manager at #{EmailAddresses::PERSONNEL}."
  end

  # Locked while signed in: the next request ends the session, as Clubhouse 2's
  # AccountGuard middleware did.
  def end_locked_session
    return unless Current.person&.locked?

    terminate_session
    redirect_to root_path, alert: locked_account_message
  end
end
